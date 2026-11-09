// Crea un account personale (Firebase Auth + employees/{uid}). Solo admin.
// Richiede header Authorization: Bearer <Firebase ID token dell'admin>.
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { generateTempPassword, isEmail, loadServiceAccount, normalizeEmail, plain, readEnv } from './_shared/confirmation.mjs';

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, authorization', 'Content-Type': 'application/json' };
const RUOLI = ['staff', 'admin', 'tricologo'];
const json = (b, s) => new Response(JSON.stringify(b), { status: s, headers: CORS });

function services() {
  const sa = loadServiceAccount(readEnv);
  if (!sa.ok) return null;
  const name = 'farmacia-employees';
  const app = getApps().find((a) => a.name === name) ?? initializeApp({ credential: cert(sa.value), projectId: sa.value.projectId }, name);
  return { auth: getAuth(app), db: getFirestore(app) };
}

export default async function createEmployee(req) {
  if (req.method === 'OPTIONS') return new Response('', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const svc = services();
  if (!svc) return json({ error: 'not_configured' }, 501);
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  let caller;
  try { caller = await svc.auth.verifyIdToken(token); } catch { return json({ error: 'unauthenticated' }, 401); }
  const me = await svc.db.collection('employees').doc(caller.uid).get();
  if (!me.exists || me.data().ruolo !== 'admin' || me.data().attivo === false) return json({ error: 'forbidden' }, 403);

  let body; try { body = await req.json(); } catch { return json({ error: 'json' }, 400); }
  const email = normalizeEmail(body?.email);
  const nome = plain(body?.nome, 100);
  const ruolo = String(body?.ruolo || '').trim().toLowerCase();
  const attivo = body?.attivo !== false;
  if (!isEmail(email) || !nome || !RUOLI.includes(ruolo)) return json({ error: 'bad_request' }, 400);

  const password = generateTempPassword(12);
  let user;
  try {
    user = await svc.auth.createUser({ email, password, displayName: nome, disabled: !attivo });
  } catch (e) {
    if (e?.code === 'auth/email-already-exists') return json({ error: 'email_exists' }, 409);
    console.error(JSON.stringify({ event: 'create_employee_failed', code: e?.code }));
    return json({ error: 'auth_error' }, 500);
  }
  await svc.db.collection('employees').doc(user.uid).set({ email, nome, ruolo, attivo });
  console.log(JSON.stringify({ event: 'employee_created', uid: user.uid, ruolo, by: caller.uid }));
  return json({ ok: true, uid: user.uid, email, password }, 200);
}
