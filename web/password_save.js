/* Salvataggio email+password nel password manager del browser (SPA Flutter).
   Chrome/Edge/Android: Credential Management API (PasswordCredential.store).
   Safari/Firefox e fallback: submit di un <form> HTML nativo verso un iframe nascosto. */
(function (w, d) {
  'use strict';

  function ensureForm() {
    var iframe = d.getElementById('farmacia-pw-sink');
    if (!iframe) {
      iframe = d.createElement('iframe');
      iframe.id = 'farmacia-pw-sink';
      iframe.name = 'farmacia-pw-sink';
      iframe.title = 'password-save';
      iframe.setAttribute('aria-hidden', 'true');
      iframe.tabIndex = -1;
      iframe.src = 'password-save.html';
      iframe.style.cssText = 'position:fixed;width:1px;height:1px;left:-9999px;top:0;border:0;opacity:0;pointer-events:none;';
      d.body.appendChild(iframe);
    }
    var form = d.getElementById('farmacia-native-login');
    if (!form) {
      form = d.createElement('form');
      form.id = 'farmacia-native-login';
      form.method = 'post';
      form.action = 'password-save.html';
      form.target = 'farmacia-pw-sink';
      form.setAttribute('autocomplete', 'on');
      form.setAttribute('aria-hidden', 'true');
      form.style.cssText = 'position:fixed;left:-9999px;top:0;width:20px;height:20px;opacity:0;overflow:hidden;';

      var user = d.createElement('input');
      user.type = 'email';
      user.name = 'username';
      user.id = 'farmacia-native-username';
      user.autocomplete = 'username';
      user.setAttribute('autocomplete', 'username');

      var pass = d.createElement('input');
      pass.type = 'password';
      pass.name = 'password';
      pass.id = 'farmacia-native-password';
      pass.autocomplete = 'current-password';
      pass.setAttribute('autocomplete', 'current-password');

      var submit = d.createElement('input');
      submit.type = 'submit';
      submit.value = 'Login';
      submit.tabIndex = -1;

      form.appendChild(user);
      form.appendChild(pass);
      form.appendChild(submit);
      d.body.appendChild(form);
    }
    return form;
  }

  function fromForm() {
    var form = d.getElementById('farmacia-native-login');
    if (!form) return null;
    var user = form.querySelector('[name="username"]');
    var pass = form.querySelector('[name="password"]');
    var email = ((user && user.value) || '').trim();
    var password = (pass && pass.value) || '';
    if (!email) return null;
    return { email: email, password: password };
  }

  function submitNativeForm(email, password) {
    var form = ensureForm();
    var user = form.querySelector('[name="username"]');
    var pass = form.querySelector('[name="password"]');
    if (user) user.value = email || '';
    if (pass) pass.value = password || '';
    try {
      if (typeof form.requestSubmit === 'function') form.requestSubmit();
      else form.submit();
    } catch (e) {
      try { form.submit(); } catch (e2) {}
    }
  }

  function storeWithApi(email, password) {
    if (!w.PasswordCredential || !navigator.credentials || !navigator.credentials.store) {
      return Promise.resolve(false);
    }
    try {
      var cred = new PasswordCredential({ id: email, name: email, password: password });
      return navigator.credentials.store(cred).then(function () { return true; }).catch(function () { return false; });
    } catch (e) {
      return Promise.resolve(false);
    }
  }

  w.farmaciaStorePassword = function (email, password) {
    email = (email || '').trim();
    password = password || '';
    if (!email || !password) return Promise.resolve(false);
    var stored = storeWithApi(email, password);
    try { submitNativeForm(email, password); } catch (e) {}
    // Non aspettiamo il click su «Salva»: il prompt resta visibile anche dopo la navigazione in-app.
    return Promise.race([
      stored,
      new Promise(function (resolve) { setTimeout(function () { resolve(false); }, 1200); })
    ]);
  };

  w.farmaciaGetSavedPassword = function () {
    var fallback = function () { return fromForm(); };
    if (navigator.credentials && typeof navigator.credentials.get === 'function') {
      try {
        return navigator.credentials.get({ password: true, mediation: 'optional' }).then(function (cred) {
          if (cred && cred.type === 'password' && cred.id) {
            return { email: cred.id, password: cred.password || '' };
          }
          return fallback();
        }).catch(function () { return fallback(); });
      } catch (e) {}
    }
    return Promise.resolve(fallback());
  };

  function boot() { try { ensureForm(); } catch (e) {} }
  if (d.readyState === 'loading') d.addEventListener('DOMContentLoaded', boot);
  else boot();
})(window, document);
