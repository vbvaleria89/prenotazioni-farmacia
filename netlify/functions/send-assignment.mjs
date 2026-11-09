// Notifica transazionale mirata: nessun destinatario/contenuto accettato dal browser.
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, initializeFirestore } from 'firebase-admin/firestore';
import { DEFAULT_FROM, DEFAULT_REPLY_TO, isAppointmentId, loadServiceAccount, normalizeEmail, plain, readEnv, sendReceipt } from './_shared/confirmation.mjs';

let cached;
function services(env) {
  if (cached) return cached;
  const loaded = loadServiceAccount(env);
  if (!loaded.ok) return null;
  const account = loaded.value;
  const app = getApps().find((x) => x.name === 'farmacia-assignment') ?? initializeApp({
    credential: cert(account), projectId: account.projectId,
  }, 'farmacia-assignment');
  let db;
  try { db = initializeFirestore(app, { preferRest: true }); } catch { db = getFirestore(app); }
  cached = { db, auth: getAuth(app) };
  return cached;
}

// Verifica euristica, non una garanzia che la casella esista. Nessun invito Calendar.
export function isRealEmployeeEmail(value) {
  const email = normalizeEmail(value);
  if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return false;
  const [local, domain] = email.split('@');
  if (/(?:noreply|no-reply|donotreply|placeholder|example|fake|dummy|temp|test)/i.test(local)) return false;
  if (/(?:^|\.)(?:example\.(?:com|org|net)|test|invalid|localhost)$/.test(domain)) return false;
  if (/(?:temp|example|fake|placeholder|mailinator|yopmail)/.test(domain)) return false;
  return true;
}

export function assignmentMessage(a, appointmentId) {
  const date = a.start?.toDate?.();
  const when = date ? new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', dateStyle: 'short', timeStyle: 'short',
  }).format(date) : 'Da verificare in app';
  const service = plain(a.servizioNome || a.servizio, 120);
  const room = plain(a.roomName || `Stanza ${a.roomId || 1}`, 80);
  const code = appointmentId.slice(0, 6).toUpperCase();
  return {
    subject: `Ti è stato assegnato: ${service}`,
    text: `Ti è stato assegnato un servizio.\n\n${service}\nData/ora: ${when} (Europe/Rome)\n${room}\nCodice: ${code}\n\nIl tuo calendario personale: https://farmacia-san-ciro-prenota.vercel.app\nAccedi all’area staff e scegli Calendario → Solo io.`,
  };
}

const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers });

export async function handleAssignment(req, deps = {}) {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const bearer = req.headers.get('authorization')?.match(/^Bearer (.+)$/)?.[1];
  if (!bearer) return json({ error: 'unauthorized' }, 401);
  const env = deps.env ?? readEnv;
  let sdk;
  try { sdk = deps.services ?? services(env); } catch {
    console.error('assignment: bad_service_account');
    return json({ ok: false, error: 'not_configured' }, 503);
  }
  if (!sdk) {
    console.warn('assignment: firebase_not_configured');
    return json({ ok: false, error: 'not_configured' }, 503);
  }
  let user;
  try { user = await sdk.auth.verifyIdToken(bearer); } catch { return json({ error: 'unauthorized' }, 401); }
  let body;
  try { body = await req.json(); } catch { return json({ error: 'json' }, 400); }
  const id = body?.appointmentId;
  if (typeof id !== 'string' || !isAppointmentId(id)) return json({ error: 'bad_request' }, 400);
  const { db } = sdk;
  try {
    // Il registro privato è accessibile soltanto all'Admin SDK (nessuna regola allargata).
    const stateRef = db.doc(`_assignmentDelivery/${id}`);
    const delivery = await db.runTransaction(async (tx) => {
      const appt = await tx.get(db.doc(`appointments/${id}`));
      if (!appt.exists) return { error: 'not_found', status: 404 };
      const a = appt.data();
      const caller = await tx.get(db.doc(`employees/${user.uid}`));
      if (!(caller.exists && caller.data().attivo !== false) && a.createdBy !== user.uid && a.clienteUid !== user.uid) {
        return { error: 'forbidden', status: 403 };
      }
      if (!['inAttesa', 'confermato'].includes(a.status)) return { skipped: 'inactive' };
      const target = typeof a.employeeId === 'string' ? a.employeeId.trim() : '';
      const stateDoc = await tx.get(stateRef);
      const state = stateDoc.exists ? stateDoc.data() : {};
      // Retry della stessa assegnazione: non crea nuove notifiche né altre email.
      if (state.employeeId === target) return target ? state : { skipped: 'unassigned' };
      const generation = (state.generation || 0) + 1;
      if (!target) {
        tx.set(stateRef, { employeeId: '', generation, updatedAt: FieldValue.serverTimestamp() });
        return { skipped: 'unassigned' };
      }
      if (target.includes('/') || target.length > 128) return { skipped: 'invalid_employee' };
      const employee = await tx.get(db.doc(`employees/${target}`));
      if (!employee.exists || employee.data().attivo === false) return { skipped: 'inactive_employee' };
      const to = normalizeEmail(employee.data().email);
      const message = assignmentMessage(a, id);
      const notificationId = `assegnazione_${id}_${generation}`;
      const next = { employeeId: target, generation, notificationId, to,
        message, emailSent: false };
      tx.set(stateRef, { ...next, updatedAt: FieldValue.serverTimestamp() });
      return next;
    });
    if (delivery.error) return json({ error: delivery.error }, delivery.status);
    if (delivery.skipped) return json({ ok: true, skipped: delivery.skipped });
    if (delivery.emailSent) return json({ ok: true, inApp: true, email: 'already_sent' });
    if (!isRealEmployeeEmail(delivery.to)) return json({ ok: true, inApp: true, email: 'skipped_invalid' });
    const apiKey = env('RESEND_API_KEY');
    if (!apiKey) {
      console.warn('assignment: mail_not_configured');
      return json({ ok: true, inApp: true, email: 'not_configured' });
    }
    const sent = await sendReceipt({ fetchImpl: deps.fetch ?? fetch, apiKey,
      payload: { from: env('MAIL_FROM') || DEFAULT_FROM, to: [delivery.to],
        reply_to: env('MAIL_REPLY_TO') || DEFAULT_REPLY_TO, ...delivery.message },
      idempotencyKey: `assignment/${id}/${delivery.generation}`, sleep: deps.sleep });
    if (sent.ok) {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(stateRef);
        if (current.data()?.generation === delivery.generation) tx.update(stateRef, { emailSent: true });
      });
    } else { console.warn('assignment: mail_send_failed'); }
    return json({ ok: true, inApp: true, email: sent.ok ? 'sent' : 'failed' });
  } catch (error) {
    console.error('assignment: operation_failed', error?.code || 'unknown');
    return json({ ok: false, error: 'assignment_failed' }, 503);
  }
}
export default handleAssignment;
