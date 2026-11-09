import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { getApps } from 'firebase-admin/app';
import { isValidCodiceFiscale } from './codice_fiscale.mjs';
import {
  TEMP_PASSWORD_ALPHABET,
  buildConfirmation,
  generateTempPassword,
  loadServiceAccount,
  provisionCustomerAccount,
  sendReceipt,
} from './confirmation.mjs';
import { firestoreAdapter, handleConfirmation } from '../send-confirmation.mjs';

const PEM = '-----BEGIN PRIVATE KEY-----\\nQUJD\\n-----END PRIVATE KEY-----\\n';
const APPT_ID = 'abcd12WXYZ12345678';
const CODICE = 'ABCD12';

function envOf(map = {}) {
  return (name) => (map[name] == null || map[name] === '' ? undefined : map[name]);
}

function post(body, method = 'POST') {
  return new Request('https://farmacia.test/send-confirmation', {
    method,
    headers: { 'content-type': 'application/json' },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
}

function bookingBody(overrides = {}) {
  return {
    to: 'Mario.Rossi@Example.com',
    nome: 'Mario Rossi',
    codice: CODICE,
    servizio: 'Holter',
    quando: '04/11/2026 alle 10:00',
    appointmentId: APPT_ID,
    ...overrides,
  };
}

function installAuth(initial = []) {
  const users = new Map(initial.map((user) => [user.email, { disabled: false, ...user }]));
  const calls = { create: 0, reset: 0 };
  let seq = users.size;
  return {
    users,
    calls,
    auth: {
      async getUserByEmail(email) {
        const user = users.get(email);
        if (!user) {
          const error = new Error('missing');
          error.code = 'auth/user-not-found';
          throw error;
        }
        return user;
      },
      async createUser(data) {
        calls.create += 1;
        if (users.has(data.email)) {
          const error = new Error('exists');
          error.code = 'auth/email-already-exists';
          throw error;
        }
        seq += 1;
        const user = {
          uid: `uid-${seq}`,
          email: data.email,
          displayName: data.displayName,
          disabled: false,
          password: data.password,
        };
        users.set(data.email, user);
        return user;
      },
      async generatePasswordResetLink(email) {
        calls.reset += 1;
        return `https://farmacia-san-ciro-prenota.netlify.app/reset?for=${encodeURIComponent(email)}`;
      },
    },
  };
}

function installStore(appointment, employees = new Set()) {
  const links = [];
  const customers = [];
  return {
    links,
    customers,
    async getAppointment(id) {
      if (!appointment || appointment.id !== id) return null;
      return appointment;
    },
    async isEmployee(uid) {
      return employees.has(uid);
    },
    async linkAppointment(id, fields) {
      links.push({ id, fields });
    },
    async saveCustomer(profile) {
      customers.push(profile);
    },
  };
}

function matchingAppointment(email = 'mario.rossi@example.com') {
  return { id: APPT_ID, clienteEmail: email };
}

async function run(body, { authBox, store, env, fetchImpl, failAuth } = {}) {
  const sent = [];
  const fetchFn = fetchImpl ?? (async (_url, init) => {
    sent.push({ headers: init.headers, body: JSON.parse(init.body) });
    return new Response('{"id":"email_1"}', { status: 200 });
  });
  const box = authBox ?? installAuth();
  const mem = store ?? installStore(matchingAppointment());
  const appsBefore = getApps().length;
  const response = await handleConfirmation(post(body), {
    env: env ?? envOf({ RESEND_API_KEY: 're_test' }),
    auth: failAuth ? undefined : box.auth,
    store: failAuth ? undefined : mem,
    fetch: fetchFn,
    sleep: async () => {},
    generatePassword: () => 'TempPassw0rd',
  });
  const raw = await response.text();
  return { response, raw, json: raw ? JSON.parse(raw) : null, sent, box, mem, appsBefore };
}

describe('password e service account', () => {
  it('genera una password temporanea nel alfabeto previsto', () => {
    const password = generateTempPassword(12, () => 1);
    assert.equal(password, TEMP_PASSWORD_ALPHABET[1].repeat(12));
    const random = generateTempPassword();
    assert.equal(random.length, 12);
    assert.match(random, new RegExp(`^[${TEMP_PASSWORD_ALPHABET}]+$`));
    assert.throws(() => generateTempPassword(6), /password_length/);
  });

  it('legge il JSON, il base64 e i tre pezzi, senza accettare una chiave monca', () => {
    const json = JSON.stringify({
      project_id: 'farmacia-san-ciro-prenota',
      client_email: 'sdk@farmacia-san-ciro-prenota.iam.gserviceaccount.com',
      private_key: PEM,
    });
    const fromJson = loadServiceAccount(envOf({ FIREBASE_SERVICE_ACCOUNT: json }));
    assert.equal(fromJson.ok, true);
    assert.equal(fromJson.value.projectId, 'farmacia-san-ciro-prenota');
    assert.equal(fromJson.value.privateKey, '-----BEGIN PRIVATE KEY-----\nQUJD\n-----END PRIVATE KEY-----');

    const fromB64 = loadServiceAccount(envOf({ FIREBASE_SERVICE_ACCOUNT: Buffer.from(json).toString('base64') }));
    assert.equal(fromB64.ok, true);
    assert.equal(fromB64.value.clientEmail, fromJson.value.clientEmail);

    const fromPieces = loadServiceAccount(envOf({
      FIREBASE_PROJECT_ID: 'farmacia-san-ciro-prenota',
      FIREBASE_CLIENT_EMAIL: 'sdk@farmacia-san-ciro-prenota.iam.gserviceaccount.com',
      FIREBASE_PRIVATE_KEY: PEM,
    }));
    assert.equal(fromPieces.ok, true);

    assert.deepEqual(loadServiceAccount(envOf({})), { ok: false, missing: true });
    const bad = loadServiceAccount(envOf({ FIREBASE_SERVICE_ACCOUNT: '{nope' }));
    assert.equal(bad.ok, false);
    assert.equal(bad.missing, false);
    const incomplete = loadServiceAccount(envOf({ FIREBASE_PROJECT_ID: 'farmacia-san-ciro-prenota' }));
    assert.equal(incomplete.ok, false);
    assert.equal(incomplete.missing, false);
  });
});

describe('testo della ricevuta', () => {
  it('include la password solo per un account appena creato e la escapa', () => {
    const created = buildConfirmation({
      nome: 'Ada <script> & "x"',
      codice: CODICE,
      servizio: 'Holter',
      quando: '04/11/2026 alle 10:00',
      to: 'ada@example.com',
      account: { status: 'created', password: 'Segreta99', resetLink: 'https://example.test/reset?a=1&b=2' },
    });
    assert.match(created.subject, /ABCD12/);
    assert.match(created.html, /Ada &lt;script&gt; &amp; &quot;x&quot;/);
    assert.doesNotMatch(created.html, /<script>/);
    assert.match(created.html, /Segreta99/);
    assert.match(created.text, /Segreta99/);
    assert.match(created.html, /a=1&amp;b=2/);
    assert.match(created.html, /lang="it"/);

    const staff = buildConfirmation({
      nome: 'Ada',
      codice: CODICE,
      servizio: 'Holter',
      quando: 'oggi',
      to: 'ada@example.com',
      account: { status: 'staff', password: 'Segreta99', resetLink: 'https://example.test/reset' },
    });
    assert.doesNotMatch(staff.html, /Segreta99/);
    assert.doesNotMatch(staff.html, /example\.test\/reset/);
    assert.match(staff.html, /account del personale/);
  });
});

describe('provisionCustomerAccount', () => {
  it('crea l\'utente, collega la prenotazione e non duplica se l\'email esiste', async () => {
    const authBox = installAuth();
    const store = installStore(matchingAppointment('Mario.Rossi@Example.com'));
    const created = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario Rossi',
      appointmentId: APPT_ID,
      codice: CODICE,
      generatePassword: () => 'TempPassw0rd',
    });
    assert.equal(created.status, 'created');
    assert.equal(created.password, 'TempPassw0rd');
    assert.equal(created.linked, true);
    assert.equal(authBox.calls.create, 1);
    assert.equal(store.links[0].fields.clienteUid, created.uid);
    assert.equal(store.links[0].fields.clienteAccount, 'created');
    assert.match(created.resetLink, /reset\?for=mario/);

    const again = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario Rossi',
      appointmentId: APPT_ID,
      codice: CODICE,
      generatePassword: () => 'AltraPassword',
    });
    assert.equal(again.status, 'existing');
    assert.equal(again.password, undefined);
    assert.equal(authBox.calls.create, 1);
    assert.equal(authBox.users.size, 1);
    assert.match(again.resetLink, /reset\?for=mario/);
  });

  it('se la create perde la gara con un utente già nato, non fallisce', async () => {
    const authBox = installAuth();
    const realCreate = authBox.auth.createUser;
    authBox.auth.createUser = async (data) => {
      await realCreate.call(authBox.auth, data);
      const error = new Error('exists');
      error.code = 'auth/email-already-exists';
      throw error;
    };
    const store = installStore(matchingAppointment());
    const result = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
    });
    assert.equal(result.status, 'existing');
    assert.equal(result.password, undefined);
    assert.equal(authBox.users.size, 1);
    assert.equal(result.linked, true);
  });

  it('non tocca la password di un dipendente e non manda il reset', async () => {
    const authBox = installAuth([{ uid: 'staff-1', email: 'mario.rossi@example.com' }]);
    authBox.auth.generatePasswordResetLink = async () => {
      throw new Error('reset non previsto');
    };
    const store = installStore(matchingAppointment(), new Set(['staff-1']));
    const result = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
      generatePassword: () => 'NonDeveComparire',
    });
    assert.equal(result.status, 'staff');
    assert.equal(result.password, undefined);
    assert.equal(result.resetLink, undefined);
    assert.equal(authBox.calls.create, 0);
    assert.equal(store.links[0].fields.clienteAccount, 'staff');
    assert.equal(store.customers.length, 0);
  });

  it('account disattivato: collega, senza link di reset', async () => {
    const authBox = installAuth([{ uid: 'u-off', email: 'mario.rossi@example.com', disabled: true }]);
    authBox.auth.generatePasswordResetLink = async () => {
      throw new Error('reset non previsto');
    };
    const store = installStore(matchingAppointment());
    const result = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
    });
    assert.equal(result.status, 'existing');
    assert.equal(result.disabled, true);
    assert.equal(result.resetLink, undefined);
    assert.equal(result.linked, true);
  });

  it('email o codice diversi: nessun utente', async () => {
    const authBox = installAuth();
    const mismatch = await provisionCustomerAccount({
      auth: authBox.auth,
      store: installStore(matchingAppointment('altro@example.com')),
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
    });
    assert.equal(mismatch.status, 'skipped');
    assert.equal(mismatch.reason, 'email_mismatch');
    assert.equal(authBox.calls.create, 0);

    const badCode = await provisionCustomerAccount({
      auth: authBox.auth,
      store: installStore(matchingAppointment()),
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: 'ZZZZZZ',
    });
    assert.equal(badCode.reason, 'code_mismatch');
    assert.equal(authBox.users.size, 0);
  });

  it('se il collegamento Firestore fallisce, la password resta disponibile per la mail', async () => {
    const authBox = installAuth();
    const store = installStore(matchingAppointment());
    store.linkAppointment = async () => {
      const error = new Error('denied');
      error.code = 'permission-denied';
      throw error;
    };
    const result = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
      generatePassword: () => 'TempPassw0rd',
    });
    assert.equal(result.status, 'created');
    assert.equal(result.password, 'TempPassw0rd');
    assert.equal(result.linked, false);
  });

  it('se non si capisce se è staff, niente reset per un utente già esistente', async () => {
    const authBox = installAuth([{ uid: 'u-1', email: 'mario.rossi@example.com' }]);
    authBox.auth.generatePasswordResetLink = async () => {
      throw new Error('reset non previsto');
    };
    const store = installStore(matchingAppointment());
    store.isEmployee = async () => {
      const error = new Error('timeout');
      error.code = 'unavailable';
      throw error;
    };
    const result = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario',
      appointmentId: APPT_ID,
      codice: CODICE,
    });
    assert.equal(result.status, 'existing');
    assert.equal(result.resetLink, undefined);
    assert.equal(result.reason, 'employee_check_failed');
    assert.equal(result.linked, false);
  });

  it('salva il codice fiscale sul profilo e non lo usa come password', async () => {
    const cf = 'RSSMRA85T10A562S';
    assert.equal(isValidCodiceFiscale(cf), true);
    const authBox = installAuth();
    const store = installStore({ ...matchingAppointment(), clienteCodiceFiscale: cf, clienteNome: 'Mario Rossi', clienteTel: '3331234567' });
    const created = await provisionCustomerAccount({
      auth: authBox.auth,
      store,
      email: 'mario.rossi@example.com',
      displayName: 'Mario Rossi',
      appointmentId: APPT_ID,
      codice: CODICE,
      generatePassword: () => 'TempPassw0rd',
    });
    assert.equal(created.password, 'TempPassw0rd');
    assert.notEqual(created.password, cf);
    assert.equal(authBox.users.get('mario.rossi@example.com').password, 'TempPassw0rd');
    assert.equal(store.customers[0].codiceFiscale, cf);
    assert.notEqual(store.customers[0].codiceFiscale, store.customers[0] && created.password);
    const mail = buildConfirmation({
      nome: 'Mario Rossi', codice: CODICE, servizio: 'Holter', quando: 'oggi', to: 'mario.rossi@example.com',
      codiceFiscale: cf,
      account: { status: 'created', password: created.password, resetLink: created.resetLink },
    });
    assert.match(mail.html, /TempPassw0rd/);
    assert.match(mail.html, new RegExp(cf));
    assert.match(mail.text, /non è il codice fiscale/);
    assert.equal(mail.html.includes(`Password temporanea</p>\n<p style="font-family:Consolas,Menlo,monospace;font-size:24px;font-weight:700;letter-spacing:1px;color:#32448C;margin:0 0 8px;">${cf}`), false);
  });
});

describe('handleConfirmation', () => {
  it('crea l\'account, manda ricevuta e credenziali, e non rimanda la password al browser', async () => {
    const ran = await run(bookingBody());
    assert.equal(ran.response.status, 200);
    assert.equal(ran.json.account, 'created');
    assert.equal(ran.json.linked, true);
    assert.equal(ran.json.ok, true);
    assert.equal(ran.raw.includes('TempPassw0rd'), false);
    assert.equal(ran.raw.includes('reset?for='), false);
    assert.match(ran.sent[0].body.html, /TempPassw0rd/);
    assert.match(ran.sent[0].body.text, /TempPassw0rd/);
    assert.equal(ran.sent[0].body.to[0], 'mario.rossi@example.com');
    assert.equal(ran.sent[0].body.from, 'Farmacia San Ciro <prenotazioni@farmaciasanciro.net>');
    assert.equal(ran.sent[0].body.reply_to, 'farmaciasanciro@gmail.com');
    assert.equal(ran.sent[0].headers['Idempotency-Key'], `booking-receipt/${APPT_ID}/created`);
    assert.equal(ran.mem.links.at(-1).fields.receiptSentAt != null, true);
    assert.equal(getApps().length, ran.appsBefore);
  });

  it('utente già presente: mail senza password nuova', async () => {
    const authBox = installAuth([{ uid: 'u-9', email: 'mario.rossi@example.com' }]);
    const ran = await run(bookingBody(), { authBox });
    assert.equal(ran.json.account, 'existing');
    assert.equal(ran.box.calls.create, 0);
    assert.doesNotMatch(ran.sent[0].body.html, /Password temporanea/);
    assert.match(ran.sent[0].body.html, /Esiste già un account/);
    assert.match(ran.sent[0].body.html, /reset\?for=/);
    assert.equal(ran.raw.includes('reset?for='), false);
  });

  it('prenotazione inesistente o email diversa: nessuna mail e nessun utente', async () => {
    const missing = await run(bookingBody({ appointmentId: 'missing12345678' }), {
      store: installStore(null),
    });
    assert.equal(missing.response.status, 409);
    assert.equal(missing.json.error, 'appointment_mismatch');
    assert.equal(missing.json.accountReason, 'appointment_not_found');
    assert.equal(missing.sent.length, 0);
    assert.equal(missing.box.calls.create, 0);

    const other = await run(bookingBody(), {
      store: installStore(matchingAppointment('altro@example.com')),
    });
    assert.equal(other.response.status, 409);
    assert.equal(other.json.accountReason, 'email_mismatch');
    assert.equal(other.sent.length, 0);
    assert.equal(other.box.users.size, 0);
  });

  it('senza appointmentId spedisce solo la ricevuta', async () => {
    const ran = await run(bookingBody({ appointmentId: '' }));
    assert.equal(ran.json.account, 'skipped');
    assert.equal(ran.json.accountReason, 'no_appointment');
    assert.equal(ran.box.calls.create, 0);
    assert.equal(ran.sent.length, 1);
    assert.doesNotMatch(ran.sent[0].body.html, /Password temporanea/);
  });

  it('service account assente o illeggibile: la ricevuta parte, l\'account no', async () => {
    const missing = await run(bookingBody(), {
      failAuth: true,
      env: envOf({ RESEND_API_KEY: 're_test' }),
    });
    assert.equal(missing.response.status, 200);
    assert.equal(missing.json.account, 'not_configured');
    assert.equal(missing.sent.length, 1);

    const bad = await run(bookingBody(), {
      failAuth: true,
      env: envOf({ RESEND_API_KEY: 're_test', FIREBASE_SERVICE_ACCOUNT: '{rotto' }),
    });
    assert.equal(bad.response.status, 200);
    assert.equal(bad.json.account, 'error');
    assert.equal(bad.json.accountReason, 'bad_service_account');
    assert.equal(bad.raw.includes('PRIVATE KEY'), false);
  });

  it('un errore Auth non blocca la ricevuta e non stampa la password', async () => {
    const authBox = installAuth();
    authBox.auth.getUserByEmail = async () => {
      const error = new Error('secret TempPassw0rd exploded');
      error.code = 'auth/internal-error';
      throw error;
    };
    const ran = await run(bookingBody(), { authBox });
    assert.equal(ran.response.status, 200);
    assert.equal(ran.json.account, 'error');
    assert.equal(ran.json.accountReason, 'auth/internal-error');
    assert.equal(ran.sent.length, 1);
    assert.equal(ran.raw.includes('TempPassw0rd'), false);
    assert.doesNotMatch(ran.sent[0].body.html, /Password temporanea/);
  });

  it('se Resend fallisce dopo la creazione, 502 senza password nel JSON', async () => {
    let attempts = 0;
    const ran = await run(bookingBody(), {
      fetchImpl: async () => {
        attempts += 1;
        return new Response('{"message":"no"}', { status: 500 });
      },
    });
    assert.equal(attempts, 3);
    assert.equal(ran.response.status, 502);
    assert.equal(ran.json.ok, false);
    assert.equal(ran.json.account, 'created');
    assert.equal(ran.json.error, 'send_failed');
    assert.equal(ran.raw.includes('TempPassw0rd'), false);
    assert.equal(ran.box.users.size, 1);
  });

  it('riprova su 500 e tratta 409 come già spedita', async () => {
    let attempts = 0;
    const retried = await run(bookingBody(), {
      fetchImpl: async (_url, init) => {
        attempts += 1;
        if (attempts === 1) return new Response('busy', { status: 500 });
        assert.equal(init.headers['Idempotency-Key'], `booking-receipt/${APPT_ID}/created`);
        return new Response('{"id":"email_2"}', { status: 200 });
      },
    });
    assert.equal(attempts, 2);
    assert.equal(retried.response.status, 200);

    const duplicate = await run(bookingBody(), {
      fetchImpl: async () => new Response('conflict', { status: 409 }),
    });
    assert.equal(duplicate.response.status, 200);
    assert.equal(duplicate.json.ok, true);
  });

  it('rifiuta la richiesta malformata e non chiama Resend senza chiave', async () => {
    const bad = await run(bookingBody({ to: 'non-una-email', codice: 'NO' }));
    assert.equal(bad.response.status, 400);
    assert.equal(bad.sent.length, 0);

    const noKey = await handleConfirmation(post(bookingBody()), {
      env: envOf({}),
      fetch: async () => {
        throw new Error('non doveva partire');
      },
    });
    assert.equal(noKey.status, 501);

    const options = await handleConfirmation(new Request('https://farmacia.test/send', { method: 'OPTIONS' }), {
      env: envOf({ RESEND_API_KEY: 're_test' }),
    });
    assert.equal(options.status, 200);
  });
});

describe('sendReceipt', () => {
  it('non ritenta un 400', async () => {
    let calls = 0;
    const result = await sendReceipt({
      apiKey: 're_test',
      idempotencyKey: 'booking-receipt/x/created',
      payload: { to: ['a@b.c'] },
      sleep: async () => {},
      fetchImpl: async () => {
        calls += 1;
        return new Response('bad', { status: 400 });
      },
    });
    assert.equal(calls, 1);
    assert.equal(result.ok, false);
    assert.equal(result.status, 400);
  });
});

describe('firestoreAdapter', () => {
  it('legge la prenotazione, riconosce il dipendente e fa merge', async () => {
    const writes = [];
    const db = {
      collection(name) {
        return {
          doc(id) {
            return {
              async get() {
                if (name === 'appointments' && id === APPT_ID) {
                  return { exists: true, id, data: () => ({ clienteEmail: 'ada@example.com' }) };
                }
                if (name === 'employees' && id === 'staff-1') return { exists: true, id, data: () => ({}) };
                return { exists: false, id, data: () => undefined };
              },
              async set(fields, options) {
                writes.push({ name, id, fields, options });
              },
            };
          },
        };
      },
    };
    const store = firestoreAdapter(db);
    assert.deepEqual(await store.getAppointment(APPT_ID), {
      id: APPT_ID,
      clienteEmail: 'ada@example.com',
      clienteNome: '',
      clienteTel: '',
      clienteCodiceFiscale: '',
    });
    assert.equal(await store.getAppointment('missing1'), null);
    assert.equal(await store.isEmployee('staff-1'), true);
    assert.equal(await store.isEmployee('uid-cliente'), false);
    await store.linkAppointment(APPT_ID, { clienteUid: 'uid-1' });
    assert.equal(writes[0].options.merge, true);
    assert.equal(writes[0].fields.clienteUid, 'uid-1');
  });
});
