import test from 'node:test';
import assert from 'node:assert/strict';
import { handleAssignment, isRealEmployeeEmail, assignmentMessage } from '../send-assignment.mjs';

const id = 'ABCDEFGH123456789012';
function request(body = { appointmentId: id }, token = true) {
  return new Request('https://app.test/api/send-assignment', { method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer mock-token' } : {}) }, body: JSON.stringify(body) });
}
function fixture({ caller = 'staff', email = 'anna@farmacia.it', mail = true } = {}) {
  const records = new Map([
    [`appointments/${id}`, { createdBy: 'creator', employeeId: 'anna', status: 'inAttesa',
      servizioNome: 'Servizio', start: { toDate: () => new Date('2026-11-06T13:00:00Z') }, roomId: 2 }],
    ['employees/staff', { attivo: true }], ['employees/anna', { email, attivo: true }],
    ['employees/vincenzo', { email: 'vincenzo@farmacia.it', attivo: true }],
  ]);
  const calls = [];
  const db = { doc: (path) => ({ path }), runTransaction: async (fn) => fn({
    get: async (ref) => ({ exists: records.has(ref.path), data: () => records.get(ref.path) }),
    set: (ref, data) => records.set(ref.path, data),
    update: (ref, data) => records.set(ref.path, { ...records.get(ref.path), ...data }),
  }) };
  const deps = { services: { db, auth: { verifyIdToken: async () => ({ uid: caller }) } },
    env: (name) => name === 'RESEND_API_KEY' && mail ? 'mock-key' : '',
    fetch: async (url, opts) => { calls.push({ url, opts, payload: JSON.parse(opts.body) }); return new Response('{"id":"mock-mail"}', { status: 200 }); },
    sleep: async () => {},
  };
  return { records, calls, deps };
}

test('euristica email: trim e indirizzi veri; esclusi placeholder', () => {
  assert.equal(isRealEmployeeEmail(' Anna@Farmacia.it '), true);
  for (const email of ['', 'bad', 'a@b', 'test@gmail.com', 'temp123@farmacia.it', 'noreply@farmacia.it', 'a@example.com', 'a@foo.invalid', 'a@mailinator.com']) assert.equal(isRealEmployeeEmail(email), false, email);
});
test('testo data Europe/Rome e nessun dato cliente', () => {
  const m = assignmentMessage({ servizioNome: 'Servizio', start: { toDate: () => new Date('2026-11-06T13:00:00Z') }, roomId: 2,
    clienteNome: 'DATOPRIVATO', clienteTel: '123456789', ricettaNote: 'SEGRETO' }, id);
  assert.match(m.text, /14:00/); assert.match(m.text, /Stanza 2/); assert.match(m.text, /ABCDEF/);
  assert.doesNotMatch(JSON.stringify(m), /DATOPRIVATO|123456789|SEGRETO/);
});
test('no autenticazione e token invalido: nessun invio', async () => {
  const f = fixture();
  assert.equal((await handleAssignment(request({}, false), f.deps)).status, 401);
  f.deps.services.auth.verifyIdToken = async () => { throw new Error(); };
  assert.equal((await handleAssignment(request(), f.deps)).status, 401);
  assert.equal(f.calls.length, 0);
});
test('estraneo e path injection negati', async () => {
  const f = fixture({ caller: 'stranger' });
  assert.equal((await handleAssignment(request(), f.deps)).status, 403);
  assert.equal((await handleAssignment(request({ appointmentId: '../users' }), f.deps)).status, 400);
  assert.equal(f.calls.length, 0);
});
test('destinatario solo da database e retry idempotente', async () => {
  const f = fixture();
  const r = await handleAssignment(request({ appointmentId: id, to: 'attacker@evil.com', servizio: 'iniettato' }), f.deps);
  assert.equal((await r.json()).email, 'sent');
  assert.deepEqual(f.calls[0].payload.to, ['anna@farmacia.it']);
  assert.equal(f.calls[0].payload.subject, 'Ti è stato assegnato: Servizio');
  assert.match(f.calls[0].opts.headers['Idempotency-Key'], /assignment\//);
  assert.equal((await (await handleAssignment(request(), f.deps)).json()).email, 'already_sent');
  assert.equal(f.calls.length, 1);
});
test('cambio persona invia solo al nuovo assegnato', async () => {
  const f = fixture(); await handleAssignment(request(), f.deps);
  f.records.get(`appointments/${id}`).employeeId = 'vincenzo';
  await handleAssignment(request(), f.deps);
  assert.equal(f.calls.length, 2);
  assert.deepEqual(f.calls[1].payload.to, ['vincenzo@farmacia.it']);
  assert.notEqual(f.calls[0].opts.headers['Idempotency-Key'], f.calls[1].opts.headers['Idempotency-Key']);
});
test('placeholder, mail assente e service account assente: soft failure', async () => {
  const f = fixture({ email: 'temp@example.com' });
  assert.equal((await (await handleAssignment(request(), f.deps)).json()).email, 'skipped_invalid');
  assert.equal(f.calls.length, 0);
  const noMail = fixture({ mail: false });
  assert.equal((await (await handleAssignment(request(), noMail.deps)).json()).email, 'not_configured');
  assert.equal((await handleAssignment(request(), { env: () => '' })).status, 503);
});
test('provider in errore: prenotazione non alterata', async () => {
  const f = fixture(); f.deps.fetch = async () => new Response('{"error":"denied"}', { status: 403 });
  assert.equal((await (await handleAssignment(request(), f.deps)).json()).email, 'failed');
  assert.equal(f.records.get(`appointments/${id}`).status, 'inAttesa');
});
