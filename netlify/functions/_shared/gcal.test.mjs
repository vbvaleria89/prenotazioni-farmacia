import test from 'node:test';
import assert from 'node:assert/strict';
import {
  eventFromAppointment, shortCode, stanzaLabel, shouldHaveEvent, authorizationUrl,
  handleGcalSync, handleGcalReconcile, handleGcalStatus, handleGcalOauthStart,
  DEFAULT_CALENDAR_ID, DEFAULT_EXPECTED_EMAIL, GCAL_SCOPE,
} from './gcal.mjs';

const id = 'AbCdEfGh1234567890xy';

test('shortCode e stanza: fallback stanze default, roomName ha priorità', () => {
  assert.equal(shortCode(id), 'ABCDEF');
  assert.equal(stanzaLabel({ roomId: 1 }), 'Stanza servizi');
  assert.equal(stanzaLabel({ roomId: 2 }), 'Stanza consulenze');
  assert.equal(stanzaLabel({ roomId: 1, roomName: 'Laboratorio' }), 'Laboratorio');
  assert.equal(stanzaLabel({ roomId: 9 }), 'Stanza 9');
});

test('mapping evento: titolo Nome · Servizio e descrizione con telefono cliccabile', () => {
  const ev = eventFromAppointment(id, {
    servizioNome: 'Holter cardiaco', servizio: 'holter',
    roomId: 1, roomName: 'Stanza servizi',
    employeeNome: 'Roberta S.', employeeId: 'emp1',
    start: new Date('2026-11-09T15:00:00.000Z'),
    end: new Date('2026-11-09T15:20:00.000Z'),
    clienteNome: 'Mario Rossi', clienteTel: '3331234567', clienteCodiceFiscale: 'RSSMRA80A01H501U',
    status: 'inAttesa', pagato: true, metodoPagamento: 'carta',
  });
  assert.equal(ev.summary, 'Mario Rossi · Holter cardiaco');
  assert.equal(ev.description, [
    'Telefono: <a href="tel:+393331234567">3331234567</a>',
    'tel:+393331234567',
    'Servizio: Holter cardiaco',
    'Stanza: Stanza servizi',
    'Operatore: Roberta S.',
    'Stato: Da confermare · Pagato · Carta',
    'Codice: ABCDEF',
  ].join('\n'));
  assert.equal(ev.start, '2026-11-09T15:00:00.000Z');
  assert.equal(ev.end, '2026-11-09T15:20:00.000Z');
  assert.doesNotMatch(JSON.stringify(ev), /RSSMRA80A01H501U/);
});

test('mapping: nome assente usa email o Cliente; senza operatore e senza telefono', () => {
  const byEmail = eventFromAppointment(id, {
    servizioNome: 'ECG', clienteEmail: 'mario.rossi@example.com', roomId: 2,
    start: { seconds: Date.parse('2026-11-13T08:00:00.000Z') / 1000 },
    end: { toDate: () => new Date('2026-11-13T08:10:00.000Z') },
    status: 'confermato',
  });
  assert.equal(byEmail.summary, 'mario.rossi@example.com · ECG');
  assert.equal(byEmail.description, [
    'Servizio: ECG',
    'Stanza: Stanza consulenze',
    'Stato: Confermato',
    'Codice: ABCDEF',
  ].join('\n'));
  assert.equal(byEmail.start, '2026-11-13T08:00:00.000Z');

  const fallback = eventFromAppointment(id, { servizio: 'ecg', roomId: 2, status: 'completato',
    start: new Date('2026-11-13T08:00:00.000Z'), end: new Date('2026-11-13T08:10:00.000Z') });
  assert.equal(fallback.summary, 'Cliente · ecg');
  assert.match(fallback.description, /Stato: Effettuata/);
  assert.doesNotMatch(fallback.description, /Operatore:|Telefono:/);
});

test('shouldHaveEvent: attive sì, annullate no', () => {
  assert.equal(shouldHaveEvent({ status: 'inAttesa' }), true);
  assert.equal(shouldHaveEvent({ status: 'confermato' }), true);
  assert.equal(shouldHaveEvent({ status: 'completato' }), true);
  assert.equal(shouldHaveEvent({ status: 'annullato' }), false);
});

test('authorizationUrl: offline + consent + scope calendar.events', () => {
  const url = new URL(authorizationUrl({
    clientId: 'cid.apps.googleusercontent.com',
    redirectUri: 'https://farmacia-san-ciro-prenota.vercel.app/api/gcal-oauth-callback',
    state: 'abc',
  }));
  assert.equal(url.origin + url.pathname, 'https://accounts.google.com/o/oauth2/v2/auth');
  assert.equal(url.searchParams.get('access_type'), 'offline');
  assert.equal(url.searchParams.get('prompt'), 'consent');
  assert.equal(url.searchParams.get('response_type'), 'code');
  assert.match(url.searchParams.get('scope'), /calendar\.events/);
  assert.equal(url.searchParams.get('state'), 'abc');
  assert.ok(GCAL_SCOPE.includes('calendar.events'));
  assert.match(DEFAULT_CALENDAR_ID, /group\.calendar\.google\.com/);
  assert.equal(DEFAULT_EXPECTED_EMAIL, 'farmaciasanciro.servizi@gmail.com');
});

function request(path, { method = 'POST', token, body, cron } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (cron) headers.Authorization = `Bearer ${cron}`;
  return new Request(`https://app.test${path}`, {
    method, headers, body: body == null ? undefined : JSON.stringify(body),
  });
}

function isDelete(v) {
  return Boolean(v && typeof v === 'object' && (
    v._methodName === 'FieldValue.delete' || v.constructor?.name === 'DeleteTransform' ||
    (typeof v.isEqual === 'function' && String(v) === 'FieldValue.delete')
  ));
}

function memDb(records) {
  const store = new Map(records);
  const db = {
    doc: (path) => ({
      path,
      get: async () => ({ exists: store.has(path), data: () => store.get(path) }),
      update: async (data) => {
        const cur = { ...(store.get(path) || {}) };
        for (const [k, v] of Object.entries(data)) {
          if (isDelete(v)) delete cur[k];
          else cur[k] = v;
        }
        store.set(path, cur);
      },
      set: async (data, _opts) => {
        const cur = { ...(store.get(path) || {}) };
        for (const [k, v] of Object.entries(data)) {
          if (isDelete(v)) delete cur[k];
          else cur[k] = v;
        }
        store.set(path, cur);
      },
    }),
    collection: (name) => ({
      where: () => ({
        limit: () => ({
          get: async () => ({
            docs: [...store.entries()].filter(([k]) => k.startsWith(`${name}/`)).map(([k, v]) => ({
              id: k.slice(name.length + 1), data: () => v,
            })),
          }),
        }),
      }),
    }),
  };
  return { store, db };
}

function fixture({ caller = 'staff1', role = 'staff', connected = true, appt, secret = {} } = {}) {
  const data = appt ?? {
    createdBy: 'staff1', clienteUid: 'cust1', status: 'inAttesa',
    servizioNome: 'ECG', roomId: 1, roomName: 'Stanza servizi',
    employeeNome: 'Luigi', start: new Date('2026-11-13T08:00:00Z'), end: new Date('2026-11-13T08:10:00Z'),
  };
  const { store, db } = memDb([
    [`appointments/${id}`, data],
    ['employees/staff1', { ruolo: 'staff', attivo: true }],
    ['employees/admin1', { ruolo: 'admin', attivo: true }],
    ['employees/disabled', { ruolo: 'admin', attivo: false }],
    ['serverSecrets/gcal', connected ? { refreshToken: 'rt-1', email: DEFAULT_EXPECTED_EMAIL, ...secret } : { ...secret }],
  ]);
  const calls = [];
  const deps = {
    services: { db, auth: { verifyIdToken: async (t) => { if (t === 'bad') throw new Error('bad'); return { uid: caller }; } } },
    env: (name) => ({
      GOOGLE_OAUTH_CLIENT_SECRET: 's3cret',
      GOOGLE_OAUTH_CLIENT_ID: 'cid',
      CRON_SECRET: 'cron-s',
      GOOGLE_CALENDAR_ACCOUNT: DEFAULT_EXPECTED_EMAIL,
    }[name]),
    fetch: async (url, opts) => {
      calls.push({ url: String(url), method: opts?.method, body: opts?.body, headers: opts?.headers });
      if (String(url).includes('oauth2.googleapis.com/token')) {
        return new Response(JSON.stringify({ access_token: 'at-1', refresh_token: 'rt-1' }), { status: 200 });
      }
      if (String(url).includes('/calendars/') && opts?.method === 'POST') {
        return new Response(JSON.stringify({ id: 'evt-new' }), { status: 200 });
      }
      if (String(url).includes('/calendars/') && opts?.method === 'PATCH') {
        return new Response(JSON.stringify({ id: 'evt-old' }), { status: 200 });
      }
      if (String(url).includes('/calendars/') && opts?.method === 'DELETE') {
        return new Response(null, { status: 204 });
      }
      return new Response('{}', { status: 404 });
    },
  };
  return { store, deps, calls };
}

test('gcal-sync: 401 senza token o token invalido', async () => {
  const f = fixture();
  assert.equal((await handleGcalSync(request('/api/gcal-sync', { body: { appointmentId: id } }), f.deps)).status, 401);
  assert.equal((await handleGcalSync(request('/api/gcal-sync', { token: 'bad', body: { appointmentId: id } }), f.deps)).status, 401);
  assert.equal(f.calls.length, 0);
});

test('gcal-sync: 400 id non valido, 403 estraneo', async () => {
  const f = fixture({ caller: 'stranger' });
  assert.equal((await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: '../x' } }), f.deps)).status, 400);
  assert.equal((await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: id } }), f.deps)).status, 403);
  assert.equal(f.calls.filter((c) => String(c.url).includes('calendar')).length, 0);
});

test('gcal-sync: crea evento e salva calendarEventId', async () => {
  const f = fixture();
  const r = await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: id } }), f.deps);
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.ok, true);
  assert.equal(body.action, 'created');
  assert.equal(f.store.get(`appointments/${id}`).calendarEventId, 'evt-new');
  const post = f.calls.find((c) => c.method === 'POST' && String(c.url).includes('/events'));
  const payload = JSON.parse(post.body);
  assert.equal(payload.summary, 'Cliente · ECG');
  assert.match(payload.description, /Operatore: Luigi/);
  assert.match(payload.description, /Servizio: ECG/);
  assert.match(payload.description, /Codice: ABCDEF/);
});

test('gcal-sync: annullata elimina l\'evento', async () => {
  const f = fixture({ appt: {
    createdBy: 'staff1', status: 'annullato', calendarEventId: 'evt-old',
    servizioNome: 'ECG', roomId: 1, start: new Date(), end: new Date(),
  } });
  const r = await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: id } }), f.deps);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).action, 'deleted');
  assert.equal(f.store.get(`appointments/${id}`).calendarEventId, undefined);
  assert.ok(f.calls.some((c) => c.method === 'DELETE'));
});

test('gcal-sync: annullata senza evento non conta come rimossa', async () => {
  const f = fixture({ appt: {
    createdBy: 'staff1', status: 'annullato',
    servizioNome: 'ECG', roomId: 1, start: new Date(), end: new Date(),
  } });
  const r = await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: id } }), f.deps);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).action, 'skipped');
  assert.equal(f.calls.filter((c) => String(c.url).includes('calendar')).length, 0);
});

test('gcal-reconcile: annullate senza evento vanno in skipped, non deleted', async () => {
  const f = fixture({ appt: {
    createdBy: 'staff1', status: 'annullato',
    servizioNome: 'ECG', roomId: 1, start: new Date(), end: new Date(),
  } });
  const r = await handleGcalReconcile(request('/api/gcal-reconcile', { method: 'GET', cron: 'cron-s' }), f.deps);
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.skipped, 1);
  assert.equal(body.deleted, 0);
  assert.equal(body.created, 0);
  assert.equal(body.failed, 0);
});

test('gcal-sync: 503 se Calendar non collegato', async () => {
  const f = fixture({ connected: false });
  assert.equal((await handleGcalSync(request('/api/gcal-sync', { token: 'ok', body: { appointmentId: id } }), f.deps)).status, 503);
});

test('gcal-reconcile: 401 senza CRON_SECRET, 200 con secret', async () => {
  const f = fixture();
  assert.equal((await handleGcalReconcile(request('/api/gcal-reconcile', { method: 'GET' }), f.deps)).status, 401);
  const r = await handleGcalReconcile(request('/api/gcal-reconcile', { method: 'GET', cron: 'cron-s' }), f.deps);
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.ok, true);
  assert.equal(body.created, 1);
});

test('gcal-status e oauth-start: solo staff/admin', async () => {
  const denied = fixture({ caller: 'stranger' });
  assert.equal((await handleGcalStatus(request('/api/gcal-status', { method: 'GET', token: 'ok' }), denied.deps)).status, 403);
  assert.equal((await handleGcalOauthStart(request('/api/gcal-oauth-start', { token: 'ok' }), denied.deps)).status, 403);
  const staff = fixture({ caller: 'staff1' });
  const st = await handleGcalStatus(request('/api/gcal-status', { method: 'GET', token: 'ok' }), staff.deps);
  assert.equal(st.status, 200);
  const sj = await st.json();
  assert.equal(sj.connected, true);
  assert.equal(sj.email, DEFAULT_EXPECTED_EMAIL);
  assert.equal((await handleGcalOauthStart(request('/api/gcal-oauth-start', { token: 'ok' }), staff.deps)).status, 403);
  const admin = fixture({ caller: 'admin1' });
  const start = await handleGcalOauthStart(request('/api/gcal-oauth-start', { token: 'ok' }), admin.deps);
  assert.equal(start.status, 200);
  const uj = await start.json();
  assert.match(uj.url, /accounts\.google\.com/);
  assert.equal(admin.store.get('serverSecrets/gcal').pendingOauth.state.length, 48);
});
