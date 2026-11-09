// Logica pura e orchestrazione iniettabile per Google Calendar lato server.
// Nessun segreto in chiaro: client secret, refresh token e service account arrivano da env/deps.
import { randomBytes } from 'node:crypto';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, initializeFirestore } from 'firebase-admin/firestore';
import { isAppointmentId, loadServiceAccount, normalizeEmail, plain, readEnv } from './confirmation.mjs';

export const DEFAULT_CALENDAR_ID =
  '43dfc90185e070f4776e65524a62a6ddaf31d3c1c3b4c046743f82430f3c655e@group.calendar.google.com';
export const DEFAULT_CLIENT_ID =
  '444833221252-pivii37uqhrshlhtfq4a5i83kl5efef7.apps.googleusercontent.com';
export const DEFAULT_EXPECTED_EMAIL = 'farmaciasanciro.servizi@gmail.com';
export const DEFAULT_REDIRECT_URI =
  'https://farmacia-san-ciro-prenota.vercel.app/api/gcal-oauth-callback';
export const GCAL_SCOPE = [
  'https://www.googleapis.com/auth/calendar.events',
  'openid',
  'email',
].join(' ');
export const SECRETS_PATH = 'serverSecrets/gcal';
export const TOKEN_URL = 'https://oauth2.googleapis.com/token';
export const CALENDAR_API = 'https://www.googleapis.com/calendar/v3';
export const USERINFO_URL = 'https://openidconnect.googleapis.com/v1/userinfo';

const DEFAULT_ROOMS = { 1: 'Stanza servizi', 2: 'Stanza consulenze' };
const ACTIVE = new Set(['inAttesa', 'confermato', 'completato']);

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};

export const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, ...extra } });

export function shortCode(id) {
  const s = String(id || '');
  const cut = s.length >= 6 ? s.slice(0, 6) : s;
  return cut.toUpperCase();
}

export function toDate(value) {
  if (value == null || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value.toDate === 'function') {
    const d = value.toDate();
    return d instanceof Date && !Number.isNaN(d.getTime()) ? d : null;
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof value.seconds === 'number') return new Date(value.seconds * 1000);
  if (typeof value._seconds === 'number') return new Date(value._seconds * 1000);
  return null;
}

export function stanzaLabel(data) {
  const saved = plain(data?.roomName, 80);
  if (saved) return saved;
  const id = Number(data?.roomId) || 1;
  return DEFAULT_ROOMS[id] || `Stanza ${id}`;
}

/** Titolo e descrizione allineati a GoogleCalendarService (niente dati cliente). */
export function eventFromAppointment(id, data) {
  const service = plain(data?.servizioNome || data?.servizio, 120) || 'Prenotazione';
  const stanza = stanzaLabel(data);
  const operator = plain(data?.employeeNome, 100);
  const code = shortCode(id);
  const summary = [service, stanza, operator, code].filter(Boolean).join(' · ');
  const description = `Prenotazione app · ${stanza}${operator ? ` · Operatore: ${operator}` : ''} · codice ${code}`;
  const start = toDate(data?.start);
  const end = toDate(data?.end);
  return {
    summary,
    description,
    start: start ? start.toISOString() : null,
    end: end ? end.toISOString() : null,
  };
}

export function shouldHaveEvent(data) {
  return ACTIVE.has(String(data?.status || ''));
}

export function calendarConfig(env = readEnv) {
  const clientId = String(env('GOOGLE_OAUTH_CLIENT_ID') || DEFAULT_CLIENT_ID).trim();
  const clientSecret = String(env('GOOGLE_OAUTH_CLIENT_SECRET') || '').trim();
  const calendarId = String(env('GOOGLE_CALENDAR_ID') || DEFAULT_CALENDAR_ID).trim();
  const expectedEmail = normalizeEmail(env('GOOGLE_CALENDAR_ACCOUNT') || DEFAULT_EXPECTED_EMAIL);
  const redirectUri = String(env('GCAL_OAUTH_REDIRECT_URI') || DEFAULT_REDIRECT_URI).trim();
  return { clientId, clientSecret, calendarId, expectedEmail, redirectUri };
}

export function authorizationUrl({ clientId, redirectUri, state, scope = GCAL_SCOPE }) {
  const q = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope,
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'true',
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${q}`;
}

let cachedSdk;
export function firebaseServices(env = readEnv) {
  if (cachedSdk) return cachedSdk;
  const loaded = loadServiceAccount(env);
  if (!loaded.ok) return null;
  const account = loaded.value;
  const name = 'farmacia-gcal';
  const app = getApps().find((x) => x.name === name) ?? initializeApp({
    credential: cert(account), projectId: account.projectId,
  }, name);
  let db;
  try { db = initializeFirestore(app, { preferRest: true }); } catch { db = getFirestore(app); }
  cachedSdk = { db, auth: getAuth(app) };
  return cachedSdk;
}

export function resetFirebaseServicesForTests() { cachedSdk = undefined; }

function bearer(req) {
  return req.headers.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1] || '';
}

async function calendarFetch(accessToken, method, path, body, fetchImpl) {
  const r = await fetchImpl(CALENDAR_API + path, {
    method,
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: body == null ? undefined : JSON.stringify(body),
  });
  let parsed = null;
  let text = '';
  if (r.status !== 204 && r.status !== 205) {
    text = await r.text();
    if (text) { try { parsed = JSON.parse(text); } catch { parsed = null; } }
  }
  return { ok: r.ok, status: r.status, body: parsed, text };
}

async function exchangeTokens(config, params, fetchImpl) {
  const r = await fetchImpl(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      ...params,
    }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const err = new Error(data.error || 'token_error');
    err.status = r.status;
    throw err;
  }
  return data;
}

async function userEmail(accessToken, fetchImpl) {
  const r = await fetchImpl(USERINFO_URL, { headers: { Authorization: `Bearer ${accessToken}` } });
  const data = await r.json().catch(() => ({}));
  return normalizeEmail(data.email);
}

async function readSecret(db) {
  const snap = await db.doc(SECRETS_PATH).get();
  return snap.exists ? (snap.data() || {}) : {};
}

async function accessTokenFromSecret(secret, config, fetchImpl) {
  const refreshToken = String(secret.refreshToken || '').trim();
  if (!refreshToken) return { error: 'not_connected' };
  const data = await exchangeTokens(config, { grant_type: 'refresh_token', refresh_token: refreshToken }, fetchImpl);
  const next = data.refresh_token && data.refresh_token !== refreshToken ? data.refresh_token : null;
  return { accessToken: data.access_token, rotatedRefresh: next };
}

async function persistRotated(db, rotatedRefresh) {
  if (!rotatedRefresh) return;
  await db.doc(SECRETS_PATH).set({
    refreshToken: rotatedRefresh,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

export async function upsertCalendarEvent({ data, id, eventId, accessToken, calendarId, fetchImpl }) {
  const ev = eventFromAppointment(id, data);
  if (!ev.start || !ev.end) throw new Error('missing_dates');
  const body = { summary: ev.summary, description: ev.description, start: { dateTime: ev.start }, end: { dateTime: ev.end } };
  const encCal = encodeURIComponent(calendarId);
  const path = `/calendars/${encCal}/events`;
  if (eventId && !String(eventId).startsWith('mock-')) {
    const patched = await calendarFetch(accessToken, 'PATCH', `${path}/${encodeURIComponent(eventId)}`, body, fetchImpl);
    if (patched.ok && patched.body?.id) return patched.body.id;
    if (patched.status !== 404 && patched.status !== 410) {
      const err = new Error(`http_${patched.status}`);
      err.status = patched.status;
      throw err;
    }
  }
  const created = await calendarFetch(accessToken, 'POST', path, body, fetchImpl);
  if (!created.ok || !created.body?.id) {
    const err = new Error(`http_${created.status}`);
    err.status = created.status;
    throw err;
  }
  return created.body.id;
}

export async function deleteCalendarEvent({ eventId, accessToken, calendarId, fetchImpl }) {
  if (!eventId || String(eventId).startsWith('mock-')) return;
  const path = `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`;
  const r = await calendarFetch(accessToken, 'DELETE', path, undefined, fetchImpl);
  if (!r.ok && r.status !== 404 && r.status !== 410) {
    const err = new Error(`http_${r.status}`);
    err.status = r.status;
    throw err;
  }
}

export async function syncAppointmentRecord({ db, data, id, accessToken, calendarId, fetchImpl }) {
  const currentId = data.calendarEventId || null;
  if (!shouldHaveEvent(data)) {
    await deleteCalendarEvent({ eventId: currentId, accessToken, calendarId, fetchImpl });
    if (currentId) await db.doc(`appointments/${id}`).update({ calendarEventId: FieldValue.delete() });
    return { action: 'deleted' };
  }
  const evId = await upsertCalendarEvent({ data, id, eventId: currentId, accessToken, calendarId, fetchImpl });
  if (evId !== currentId) await db.doc(`appointments/${id}`).update({ calendarEventId: evId });
  return { action: currentId && evId === currentId ? 'updated' : 'created', calendarEventId: evId };
}

async function callerMaySync(db, user, data) {
  if (data.createdBy === user.uid || data.clienteUid === user.uid) return true;
  const emp = await db.doc(`employees/${user.uid}`).get();
  return emp.exists && emp.data()?.attivo !== false;
}

export async function handleGcalSync(req, deps = {}) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const token = bearer(req);
  if (!token) return json({ error: 'unauthorized' }, 401);
  const env = deps.env ?? readEnv;
  const sdk = deps.services ?? firebaseServices(env);
  if (!sdk) return json({ error: 'not_configured' }, 503);
  let user;
  try { user = await sdk.auth.verifyIdToken(token); } catch { return json({ error: 'unauthorized' }, 401); }
  let body;
  try { body = await req.json(); } catch { return json({ error: 'json' }, 400); }
  const id = body?.appointmentId;
  if (typeof id !== 'string' || !isAppointmentId(id)) return json({ error: 'bad_request' }, 400);
  const appt = await sdk.db.doc(`appointments/${id}`).get();
  if (!appt.exists) return json({ error: 'not_found' }, 404);
  const data = appt.data();
  if (!(await callerMaySync(sdk.db, user, data))) return json({ error: 'forbidden' }, 403);
  const config = calendarConfig(env);
  if (!config.clientSecret) return json({ error: 'not_configured' }, 503);
  const fetchImpl = deps.fetch ?? fetch;
  const secret = await readSecret(sdk.db);
  let tokens;
  try { tokens = await accessTokenFromSecret(secret, config, fetchImpl); }
  catch (e) {
    console.error(JSON.stringify({ event: 'gcal_token_failed', status: e.status || 0 }));
    return json({ error: 'not_connected' }, 503);
  }
  if (tokens.error) return json({ error: 'not_connected' }, 503);
  await persistRotated(sdk.db, tokens.rotatedRefresh);
  try {
    const result = await syncAppointmentRecord({
      db: sdk.db, data, id, accessToken: tokens.accessToken,
      calendarId: config.calendarId, fetchImpl,
    });
    return json({ ok: true, ...result });
  } catch (e) {
    console.error(JSON.stringify({ event: 'gcal_sync_failed', status: e.status || 0, code: e.message }));
    return json({ error: 'sync_failed' }, 502);
  }
}

export async function reconcileAppointments({ db, accessToken, calendarId, fetchImpl, now = new Date(), lookbackDays = 14, limit = 80 }) {
  const from = new Date(now.getTime() - lookbackDays * 86400000);
  const snap = await db.collection('appointments').where('start', '>=', from).limit(limit).get();
  const summary = { scanned: 0, created: 0, updated: 0, deleted: 0, failed: 0 };
  for (const doc of snap.docs) {
    summary.scanned++;
    try {
      const r = await syncAppointmentRecord({
        db, data: doc.data(), id: doc.id, accessToken, calendarId, fetchImpl,
      });
      if (r.action === 'created') summary.created++;
      else if (r.action === 'updated') summary.updated++;
      else if (r.action === 'deleted') summary.deleted++;
    } catch (e) {
      summary.failed++;
      console.error(JSON.stringify({ event: 'gcal_reconcile_item_failed', status: e.status || 0 }));
    }
  }
  return summary;
}

function cronAuthorized(req, env) {
  const secret = String(env('CRON_SECRET') || '').trim();
  if (!secret) return false;
  const auth = bearer(req);
  const header = req.headers.get('x-cron-secret') || '';
  return auth === secret || header === secret;
}

export async function handleGcalReconcile(req, deps = {}) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'GET' && req.method !== 'POST') return json({ error: 'method' }, 405);
  const env = deps.env ?? readEnv;
  if (!cronAuthorized(req, env)) return json({ error: 'unauthorized' }, 401);
  const sdk = deps.services ?? firebaseServices(env);
  if (!sdk) return json({ error: 'not_configured' }, 503);
  const config = calendarConfig(env);
  if (!config.clientSecret) return json({ error: 'not_configured' }, 503);
  const fetchImpl = deps.fetch ?? fetch;
  const secret = await readSecret(sdk.db);
  let tokens;
  try { tokens = await accessTokenFromSecret(secret, config, fetchImpl); }
  catch { return json({ error: 'not_connected' }, 503); }
  if (tokens.error) return json({ error: 'not_connected' }, 503);
  await persistRotated(sdk.db, tokens.rotatedRefresh);
  const result = await reconcileAppointments({
    db: sdk.db, accessToken: tokens.accessToken, calendarId: config.calendarId, fetchImpl,
  });
  return json({ ok: true, ...result });
}

export async function handleGcalStatus(req, deps = {}) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'GET') return json({ error: 'method' }, 405);
  const token = bearer(req);
  if (!token) return json({ error: 'unauthorized' }, 401);
  const env = deps.env ?? readEnv;
  const sdk = deps.services ?? firebaseServices(env);
  if (!sdk) return json({ error: 'not_configured' }, 503);
  let user;
  try { user = await sdk.auth.verifyIdToken(token); } catch { return json({ error: 'unauthorized' }, 401); }
  const emp = await sdk.db.doc(`employees/${user.uid}`).get();
  if (!emp.exists || emp.data()?.attivo === false) return json({ error: 'forbidden' }, 403);
  const secret = await readSecret(sdk.db);
  const connected = Boolean(String(secret.refreshToken || '').trim());
  return json({
    ok: true,
    connected,
    email: connected ? (secret.email || calendarConfig(env).expectedEmail) : null,
    connectedAt: secret.connectedAt?.toDate?.()?.toISOString?.() || null,
    isAdmin: emp.data()?.ruolo === 'admin',
  });
}

export async function handleGcalOauthStart(req, deps = {}) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'POST' && req.method !== 'GET') return json({ error: 'method' }, 405);
  const token = bearer(req);
  if (!token) return json({ error: 'unauthorized' }, 401);
  const env = deps.env ?? readEnv;
  const sdk = deps.services ?? firebaseServices(env);
  if (!sdk) return json({ error: 'not_configured' }, 503);
  let user;
  try { user = await sdk.auth.verifyIdToken(token); } catch { return json({ error: 'unauthorized' }, 401); }
  const me = await sdk.db.doc(`employees/${user.uid}`).get();
  if (!me.exists || me.data()?.ruolo !== 'admin' || me.data()?.attivo === false) {
    return json({ error: 'forbidden' }, 403);
  }
  const config = calendarConfig(env);
  if (!config.clientSecret) return json({ error: 'not_configured' }, 503);
  const state = randomBytes(24).toString('hex');
  const exp = Date.now() + 15 * 60 * 1000;
  await sdk.db.doc(SECRETS_PATH).set({
    pendingOauth: { state, uid: user.uid, exp },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  const url = authorizationUrl({ clientId: config.clientId, redirectUri: config.redirectUri, state });
  return json({ ok: true, url });
}

function htmlPage(title, body, status = 200) {
  const html = `<!doctype html><meta charset="utf-8"><title>${title}</title>
  <body style="font-family:system-ui,sans-serif;max-width:36rem;margin:3rem auto;padding:0 1rem;color:#1a1a1a">
  <h1 style="font-size:1.4rem">${title}</h1><p>${body}</p>
  <p style="color:#555">Puoi chiudere questa finestra e tornare all'app.</p></body>`;
  return new Response(html, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
}

function escapeHtml(s) {
  return String(s).replace(/[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}

export async function handleGcalOauthCallback(req, deps = {}) {
  if (req.method !== 'GET') return htmlPage('Errore', 'Metodo non consentito.', 405);
  const env = deps.env ?? readEnv;
  const url = new URL(req.url);
  const err = url.searchParams.get('error');
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  if (err) return htmlPage('Collegamento annullato', escapeHtml(err === 'access_denied' ? 'Il consenso è stato rifiutato.' : err));
  if (!code || !state) return htmlPage('Errore', 'Richiesta incompleta.', 400);
  const sdk = deps.services ?? firebaseServices(env);
  if (!sdk) return htmlPage('Non configurato', 'Manca la configurazione del server.', 503);
  const config = calendarConfig(env);
  if (!config.clientSecret) return htmlPage('Non configurato', 'Manca il client OAuth.', 503);
  const secret = await readSecret(sdk.db);
  const pending = secret.pendingOauth || {};
  if (!pending.state || pending.state !== state || !pending.exp || Date.now() > Number(pending.exp)) {
    return htmlPage('Sessione scaduta', 'Riapri l’app e riprova a collegare Google Calendar.', 400);
  }
  const fetchImpl = deps.fetch ?? fetch;
  let tokens;
  try {
    tokens = await exchangeTokens(config, {
      grant_type: 'authorization_code',
      code,
      redirect_uri: config.redirectUri,
    }, fetchImpl);
  } catch {
    return htmlPage('Errore', 'Non è stato possibile completare il collegamento con Google.', 502);
  }
  if (!tokens.refresh_token) {
    return htmlPage('Refresh token assente', 'Google non ha restituito un refresh token. Riprova con il consenso completo (prompt consent).', 502);
  }
  const email = await userEmail(tokens.access_token, fetchImpl);
  if (!email || email !== config.expectedEmail) {
    return htmlPage('Account non valido',
      `Devi collegare l’account <strong>${escapeHtml(config.expectedEmail)}</strong>.` +
      (email ? ` Hai usato <strong>${escapeHtml(email)}</strong>.` : ''), 403);
  }
  await sdk.db.doc(SECRETS_PATH).set({
    refreshToken: tokens.refresh_token,
    email,
    scope: tokens.scope || GCAL_SCOPE,
    connectedAt: FieldValue.serverTimestamp(),
    connectedBy: pending.uid || null,
    pendingOauth: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  try {
    const result = await reconcileAppointments({
      db: sdk.db, accessToken: tokens.access_token, calendarId: config.calendarId, fetchImpl,
    });
    return htmlPage('Google Calendar collegato',
      `Collegato come <strong>${escapeHtml(email)}</strong>. Prenotazioni allineate: create ${result.created}, aggiornate ${result.updated}, rimosse ${result.deleted}${result.failed ? `, non riuscite ${result.failed}` : ''}.`);
  } catch {
    return htmlPage('Google Calendar collegato',
      `Collegato come <strong>${escapeHtml(email)}</strong>. L’allineamento delle prenotazioni esistenti verrà ritentato automaticamente.`);
  }
}
