import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = readFileSync(join(root, 'web/password_save.js'), 'utf8');

function boot(options = {}) {
  const stored = [];
  const submitted = [];
  const children = [];
  const elements = {};
  const form = {
    id: 'farmacia-native-login',
    method: '',
    action: '',
    target: '',
    style: { cssText: '' },
    querySelector(sel) {
      if (sel.includes('username')) return this._user;
      if (sel.includes('password')) return this._pass;
      return null;
    },
    _user: { value: options.formEmail || '', name: 'username' },
    _pass: { value: options.formPassword || '', name: 'password' },
    requestSubmit() { submitted.push({ type: 'requestSubmit', email: this._user.value, password: this._pass.value }); },
    submit() { submitted.push({ type: 'submit', email: this._user.value, password: this._pass.value }); },
    appendChild(el) { children.push(el); if (el.name === 'username') this._user = el; if (el.name === 'password') this._pass = el; },
    setAttribute() {},
  };
  const body = {
    appendChild(el) {
      children.push(el);
      if (el.id) elements[el.id] = el;
    },
  };
  const document = {
    body,
    readyState: 'complete',
    getElementById(id) { return elements[id] || null; },
    createElement(tag) {
      const el = {
        tagName: tag,
        style: { cssText: '' },
        setAttribute() {},
        appendChild(child) { (this._kids ??= []).push(child); if (this.appendChildForm) this.appendChildForm(child); },
        querySelector: form.querySelector.bind(form),
        requestSubmit: form.requestSubmit.bind(form),
        submit: form.submit.bind(form),
      };
      if (tag === 'form') {
        Object.assign(el, form);
        el.appendChildForm = form.appendChild.bind(form);
        elements['farmacia-native-login'] = el;
      }
      if (tag === 'input') {
        el.type = '';
        el.name = '';
        el.id = '';
        el.value = '';
        el.autocomplete = '';
        el.tabIndex = 0;
      }
      if (tag === 'iframe') {
        el.id = '';
        el.name = '';
        el.title = '';
        el.src = '';
        el.tabIndex = 0;
      }
      return el;
    },
    addEventListener() {},
  };

  const credentials = {
    storeCalls: stored,
    getImpl: options.getImpl,
    store(cred) {
      stored.push(cred);
      if (options.storeReject) return Promise.reject(new Error('no'));
      if (options.storeHang) return new Promise(() => {});
      return Promise.resolve();
    },
    get(opts) {
      if (typeof options.getImpl === 'function') return options.getImpl(opts);
      return Promise.resolve(null);
    },
  };

  function PasswordCredential(init) {
    this.id = init.id;
    this.name = init.name;
    this.password = init.password;
    this.type = 'password';
  }

  const window = {
    PasswordCredential: options.noApi ? undefined : PasswordCredential,
    document,
  };
  const navigator = { credentials };
  window.navigator = navigator;

  const ctx = createContext({
    window,
    document,
    navigator,
    PasswordCredential: window.PasswordCredential,
    setTimeout,
    console,
  });
  runInContext(src, ctx);
  return { window, stored, submitted, form, document, credentials };
}

const api = boot();
assert.equal(typeof api.window.farmaciaStorePassword, 'function');
assert.equal(typeof api.window.farmaciaGetSavedPassword, 'function');

const r1 = await api.window.farmaciaStorePassword('mario.rossi@example.com', 'Segreta1!');
assert.equal(r1, true);
assert.equal(api.stored.length, 1);
assert.equal(api.stored[0].id, 'mario.rossi@example.com');
assert.equal(api.stored[0].password, 'Segreta1!');
assert.ok(api.submitted.length >= 1);
assert.equal(api.submitted[0].email, 'mario.rossi@example.com');
assert.equal(api.submitted[0].password, 'Segreta1!');

const empty = await api.window.farmaciaStorePassword('  ', '');
assert.equal(empty, false);

const noApi = boot({ noApi: true });
const r2 = await noApi.window.farmaciaStorePassword('anna@example.com', 'Pw2');
assert.equal(r2, false);
assert.equal(noApi.stored.length, 0);
assert.ok(noApi.submitted.length >= 1);
assert.equal(noApi.submitted[0].email, 'anna@example.com');

const hang = boot({ storeHang: true });
const t0 = Date.now();
const r3 = await hang.window.farmaciaStorePassword('a@b.it', 'x');
assert.ok(Date.now() - t0 < 2500);
assert.equal(r3, false);
assert.equal(hang.stored.length, 1);

const getter = boot({
  getImpl() {
    return Promise.resolve({ type: 'password', id: 'saved@example.com', password: 'abc' });
  },
});
const got = await getter.window.farmaciaGetSavedPassword();
assert.equal(got.email, 'saved@example.com');
assert.equal(got.password, 'abc');

const formOnly = boot({ noApi: true });
const native = formOnly.document.getElementById('farmacia-native-login');
native.querySelector('[name="username"]').value = 'form@example.com';
native.querySelector('[name="password"]').value = 'fromform';
const fromForm = await formOnly.window.farmaciaGetSavedPassword();
assert.equal(fromForm.email, 'form@example.com');
assert.equal(fromForm.password, 'fromform');

console.log('password_save.js tests ok');
