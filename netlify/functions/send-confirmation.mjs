// Ricevuta prenotazione (Resend) e, se l'email è nuova, account cliente Firebase Auth.
// Chiamata dal client DOPO il salvataggio. Un errore qui non annulla la prenotazione.
//
// Env Netlify (mai in git):
//   RESEND_API_KEY            obbligatoria per spedire
//   MAIL_FROM                 opzionale, default prenotazioni@farmaciasanciro.net
//   MAIL_REPLY_TO             opzionale, default farmaciasanciro@gmail.com
//   FIREBASE_SERVICE_ACCOUNT  JSON (o base64) del service account
//   oppure FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, initializeFirestore } from 'firebase-admin/firestore';
import {
  DEFAULT_FROM,
  DEFAULT_REPLY_TO,
  buildConfirmation,
  idempotencyKey,
  isAppointmentId,
  isCodice,
  isEmail,
  loadServiceAccount,
  normalizeEmail,
  plain,
  provisionCustomerAccount,
  readEnv,
  safeAuthCode,
  sendReceipt,
} from './_shared/confirmation.mjs';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Content-Type': 'application/json',
};

let cached;

function adminServices(serviceAccount) {
  const fingerprint = `${serviceAccount.projectId}:${serviceAccount.clientEmail}:${serviceAccount.privateKey.length}`;
  if (cached?.fingerprint === fingerprint) return cached.services;
  const name = 'farmacia-prenota';
  const existing = getApps().find((app) => app.name === name);
  const app = existing ?? initializeApp({
    credential: cert({
      projectId: serviceAccount.projectId,
      clientEmail: serviceAccount.clientEmail,
      privateKey: serviceAccount.privateKey,
    }),
    projectId: serviceAccount.projectId,
  }, name);
  let db;
  try {
    db = initializeFirestore(app, { preferRest: true });
  } catch {
    db = getFirestore(app);
  }
  const services = { auth: getAuth(app), db };
  cached = { fingerprint, services };
  return services;
}

export function firestoreAdapter(db) {
  return {
    async getAppointment(id) {
      const snap = await db.collection('appointments').doc(id).get();
      if (!snap.exists) return null;
      const data = snap.data() || {};
      return {
        id: snap.id,
        ...(data.clienteUid ? { clienteUid: data.clienteUid } : {}),
        clienteEmail: data.clienteEmail || '',
        clienteNome: data.clienteNome || '',
        clienteTel: data.clienteTel || '',
        clienteCodiceFiscale: data.clienteCodiceFiscale || '',
      };
    },
    async isEmployee(uid) {
      const snap = await db.collection('employees').doc(uid).get();
      return snap.exists === true;
    },
    async linkAppointment(id, fields) {
      await db.collection('appointments').doc(id).set(fields, { merge: true });
    },
    async saveCustomer(profile) {
      const data = {
        email: profile.email || '',
        nome: profile.nome || '',
        telefono: profile.telefono || '',
        updatedAt: new Date().toISOString(),
      };
      if (profile.codiceFiscale) data.codiceFiscale = profile.codiceFiscale;
      await db.collection('customers').doc(profile.uid).set(data, { merge: true });
    },
  };
}

function json(body, status) {
  return new Response(JSON.stringify(body), { status, headers: CORS });
}

async function resolveAccount({ env, deps, email, nome, appointmentId, codice }) {
  const empty = (account) => ({ account, store: null });
  if (!appointmentId) return empty({ status: 'skipped', reason: 'no_appointment', linked: false });
  if (deps.auth && deps.store) {
    const account = await provisionCustomerAccount({
      auth: deps.auth,
      store: deps.store,
      email,
      displayName: nome,
      appointmentId,
      codice,
      generatePassword: deps.generatePassword,
    });
    return { account, store: deps.store };
  }
  const loaded = loadServiceAccount(env);
  if (loaded.missing) return empty({ status: 'not_configured', linked: false });
  if (!loaded.ok) return empty({ status: 'error', reason: 'bad_service_account', linked: false });
  const services = adminServices(loaded.value);
  const store = firestoreAdapter(services.db);
  const account = await provisionCustomerAccount({
    auth: services.auth,
    store,
    email,
    displayName: nome,
    appointmentId,
    codice,
  });
  return { account, store };
}

export async function handleConfirmation(req, deps = {}) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  const env = deps.env ?? readEnv;
  const apiKey = env('RESEND_API_KEY');
  if (!apiKey) return json({ ok: false, error: 'not_configured' }, 501);

  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'json' }, 400);
  }

  const to = normalizeEmail(body?.to);
  const nome = plain(body?.nome, 100);
  const codice = plain(body?.codice, 12).toUpperCase();
  const servizio = plain(body?.servizio, 120);
  const quando = plain(body?.quando, 80);
  const appointmentId = String(body?.appointmentId || '').trim();

  if (!isEmail(to) || !isCodice(codice) || (appointmentId && !isAppointmentId(appointmentId))) {
    return json({ error: 'bad_request' }, 400);
  }

  let account = { status: 'skipped', reason: 'no_appointment', linked: false };
  let store = null;
  try {
    const resolved = await resolveAccount({ env, deps, email: to, nome, appointmentId, codice });
    account = resolved.account;
    store = resolved.store;
  } catch (error) {
    const code = safeAuthCode(error);
    console.error(JSON.stringify({ event: 'account_provision_failed', code }));
    account = { status: 'error', reason: code, linked: false };
  }

  // Prenotazione assente o email/codice diversi: non si crea l'account e non si spedisce
  // (evita di usare l'endpoint per scrivere a indirizzi arbitrari). Senza appointmentId
  // si mantiene l'invio della sola ricevuta, per i client già in produzione.
  const mismatch = account.status === 'skipped'
    && (account.reason === 'appointment_not_found' || account.reason === 'email_mismatch' || account.reason === 'code_mismatch');
  if (mismatch) {
    console.log(JSON.stringify({
      event: 'booking_receipt',
      appointmentId,
      account: account.status,
      reason: account.reason,
      mail: 'skipped',
    }));
    return json({ ok: false, account: account.status, linked: false, accountReason: account.reason, error: 'appointment_mismatch' }, 409);
  }

  const message = buildConfirmation({ nome, codice, servizio, quando, to, account, codiceFiscale: account.codiceFiscale });
  const payload = {
    from: env('MAIL_FROM') || DEFAULT_FROM,
    to: [to],
    reply_to: env('MAIL_REPLY_TO') || DEFAULT_REPLY_TO,
    subject: message.subject,
    html: message.html,
    text: message.text,
  };
  const delivered = await sendReceipt({
    fetchImpl: deps.fetch ?? fetch,
    apiKey,
    payload,
    idempotencyKey: idempotencyKey(appointmentId, codice, account.status),
    sleep: deps.sleep,
  });

  const summary = {
    ok: delivered.ok,
    account: account.status,
    linked: Boolean(account.linked),
    ...(account.reason ? { accountReason: account.reason } : {}),
  };
  console.log(JSON.stringify({
    event: 'booking_receipt',
    appointmentId: appointmentId || undefined,
    account: account.status,
    linked: Boolean(account.linked),
    mail: delivered.ok ? delivered.status : 'failed',
  }));

  if (delivered.ok && store && appointmentId && account.linked) {
    try {
      await store.linkAppointment(appointmentId, { receiptSentAt: new Date().toISOString() });
    } catch (error) {
      console.error(JSON.stringify({ event: 'receipt_stamp_failed', code: safeAuthCode(error) }));
    }
  }

  if (!delivered.ok) return json({ ...summary, error: 'send_failed' }, 502);
  return json(summary, 200);
}

export default function sendConfirmation(req) {
  return handleConfirmation(req);
}
