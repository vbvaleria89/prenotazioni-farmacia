// Logica pura della ricevuta: niente Firebase, niente rete.
// La function Netlify (send-confirmation.mjs) la usa dopo il salvataggio della prenotazione.
import { randomInt } from 'node:crypto';
import { isValidCodiceFiscale, normalizeCodiceFiscale } from './codice_fiscale.mjs';

export const TEMP_PASSWORD_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
export const DEFAULT_FROM = 'Farmacia San Ciro <prenotazioni@farmaciasanciro.net>';
export const DEFAULT_REPLY_TO = 'farmaciasanciro@gmail.com';
export const PASSWORD_RESET_CONTINUE_URL = 'https://farmacia-san-ciro-prenota.netlify.app';

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const CODICE_RE = /^[A-Z0-9]{4,12}$/;
const APPOINTMENT_RE = /^[A-Za-z0-9]{8,128}$/;

export function isEmail(value) {
  return EMAIL_RE.test(String(value || ''));
}

export function isCodice(value) {
  return CODICE_RE.test(String(value || ''));
}

export function isAppointmentId(value) {
  return APPOINTMENT_RE.test(String(value || ''));
}

export function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

export function plain(value, max = 200) {
  return String(value ?? '').replace(/[\r\n\t]+/g, ' ').trim().slice(0, max);
}

export function escapeHtml(value) {
  return plain(value, 500).replace(/[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}

/** Password temporanea leggibile. `nextInt(max)` deve restituire un intero in [0, max). */
export function generateTempPassword(length = 12, nextInt = (max) => randomInt(max)) {
  const size = Number(length);
  if (!Number.isInteger(size) || size < 8 || size > 64) throw new Error('password_length');
  let out = '';
  for (let i = 0; i < size; i++) out += TEMP_PASSWORD_ALPHABET[nextInt(TEMP_PASSWORD_ALPHABET.length)];
  return out;
}

export function parseServiceAccount(raw) {
  if (raw == null) return null;
  let text = typeof raw === 'string' ? raw.trim() : raw;
  if (typeof text === 'string' && text.length >= 2) {
    const quote = text[0];
    if ((quote === '"' || quote === "'") && text.endsWith(quote)) {
      try {
        const unwrapped = JSON.parse(text);
        if (typeof unwrapped === 'string') text = unwrapped.trim();
      } catch {
        text = text.slice(1, -1).trim();
      }
    }
  }
  if (typeof text === 'string' && text && !text.startsWith('{')) {
    try {
      const decoded = Buffer.from(text, 'base64').toString('utf8').trim();
      if (decoded.startsWith('{')) text = decoded;
    } catch {
      /* non è base64: si prova comunque il parse JSON sotto */
    }
  }
  const json = typeof text === 'string' ? JSON.parse(text) : text;
  if (!json || typeof json !== 'object') return null;
  let privateKey = String(json.private_key || json.privateKey || '').trim();
  if ((privateKey.startsWith('"') && privateKey.endsWith('"')) || (privateKey.startsWith("'") && privateKey.endsWith("'"))) {
    privateKey = privateKey.slice(1, -1);
  }
  privateKey = privateKey.replace(/\\n/g, '\n').trim();
  const projectId = String(json.project_id || json.projectId || '').trim();
  const clientEmail = String(json.client_email || json.clientEmail || '').trim();
  if (!privateKey.includes('BEGIN PRIVATE KEY') || !projectId || !clientEmail.includes('@')) return null;
  return { projectId, clientEmail, privateKey };
}

/**
 * @returns {{ ok: true, value: { projectId: string, clientEmail: string, privateKey: string } }
 *   | { ok: false, missing: boolean }}
 */
export function loadServiceAccount(env) {
  const raw = env('FIREBASE_SERVICE_ACCOUNT');
  const projectId = env('FIREBASE_PROJECT_ID');
  const clientEmail = env('FIREBASE_CLIENT_EMAIL');
  const privateKey = env('FIREBASE_PRIVATE_KEY');
  const hasPieces = Boolean(projectId || clientEmail || privateKey);
  if ((raw == null || String(raw).trim() === '') && !hasPieces) return { ok: false, missing: true };
  try {
    if (raw != null && String(raw).trim() !== '') {
      const value = parseServiceAccount(raw);
      return value ? { ok: true, value } : { ok: false, missing: false };
    }
    const value = parseServiceAccount({
      project_id: projectId,
      client_email: clientEmail,
      private_key: privateKey,
    });
    return value ? { ok: true, value } : { ok: false, missing: false };
  } catch {
    return { ok: false, missing: false };
  }
}

function safeAuthCode(error) {
  const code = String(error?.code || '');
  return /^[a-z0-9/_-]{1,80}$/i.test(code) ? code : 'provision_failed';
}

async function safeResetLink(auth, email) {
  try {
    return await auth.generatePasswordResetLink(email, {
      url: PASSWORD_RESET_CONTINUE_URL,
      handleCodeInApp: false,
    });
  } catch {
    try {
      return await auth.generatePasswordResetLink(email);
    } catch {
      return undefined;
    }
  }
}

/**
 * Crea l'utente email/password se manca, altrimenti collega la prenotazione.
 * Non lancia per «email già usata». Gli altri errori salgono al chiamante,
 * che manda comunque la ricevuta e non deve far fallire la prenotazione.
 */
export async function provisionCustomerAccount({
  auth,
  store,
  email,
  displayName,
  appointmentId,
  codice,
  generatePassword = () => generateTempPassword(),
}) {
  const appt = await store.getAppointment(appointmentId);
  if (!appt) return { status: 'skipped', reason: 'appointment_not_found', linked: false };
  const storedEmail = normalizeEmail(appt.clienteEmail);
  if (!storedEmail || storedEmail !== email) return { status: 'skipped', reason: 'email_mismatch', linked: false };
  const prefix = String(appt.id || appointmentId).slice(0, 6).toUpperCase();
  if (codice && prefix !== String(codice).trim().toUpperCase()) {
    return { status: 'skipped', reason: 'code_mismatch', linked: false };
  }

  // Il recapito per le ricevute non è l'identità di accesso. Una correzione del
  // banco non deve creare un secondo utente o spostare la prenotazione a un altro uid.
  // Non spediamo link di reset a un indirizzo di contatto diverso da quello Auth.
  if (appt.clienteUid) {
    const fiscal = isValidCodiceFiscale(appt.clienteCodiceFiscale) ? normalizeCodiceFiscale(appt.clienteCodiceFiscale) : '';
    return { status: 'existing', uid: appt.clienteUid, linked: true, contactOnly: true,
      ...(fiscal ? { codiceFiscale: fiscal } : {}) };
  }

  let user;
  let created = false;
  let password;
  try {
    user = await auth.getUserByEmail(email);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') throw error;
  }

  if (!user) {
    password = generatePassword();
    try {
      user = await auth.createUser({
        email,
        password,
        displayName: plain(displayName, 80) || undefined,
        emailVerified: false,
        disabled: false,
      });
      created = true;
    } catch (error) {
      if (error?.code !== 'auth/email-already-exists') throw error;
      user = await auth.getUserByEmail(email);
      password = undefined;
      created = false;
    }
  }

  const disabled = Boolean(user?.disabled);
  let staff = false;
  try {
    staff = Boolean(user?.uid) && await store.isEmployee(user.uid);
  } catch (error) {
    console.error(JSON.stringify({ event: 'employee_check_failed', code: safeAuthCode(error) }));
    // Senza la verifica non mandiamo un link di reset: potrebbe essere un account staff.
    // Se l'utente è appena stato creato, l'uid è nuovo e la password va comunque in mail.
    if (!created) {
      return { status: 'existing', uid: user.uid, linked: false, disabled, reason: 'employee_check_failed' };
    }
  }
  let resetLink;
  if (!staff && !disabled) resetLink = await safeResetLink(auth, email);

  const status = staff ? 'staff' : created ? 'created' : 'existing';
  const fiscal = isValidCodiceFiscale(appt.clienteCodiceFiscale) ? normalizeCodiceFiscale(appt.clienteCodiceFiscale) : '';
  let linked = false;
  try {
    await store.linkAppointment(appointmentId, {
      clienteUid: user.uid,
      clienteAccount: status,
      accountLinkedAt: new Date().toISOString(),
      clienteEmail: email,
      ...(fiscal ? { clienteCodiceFiscale: fiscal } : {}),
    });
    linked = true;
  } catch (error) {
    console.error(JSON.stringify({ event: 'link_failed', code: safeAuthCode(error) }));
  }

  if (status !== 'staff' && typeof store.saveCustomer === 'function') {
    try {
      await store.saveCustomer({
        uid: user.uid,
        email,
        nome: plain(appt.clienteNome || displayName, 100),
        telefono: plain(appt.clienteTel, 30),
        ...(fiscal ? { codiceFiscale: fiscal } : {}),
      });
    } catch (error) {
      console.error(JSON.stringify({ event: 'customer_profile_failed', code: safeAuthCode(error) }));
    }
  }

  return {
    status,
    uid: user.uid,
    linked,
    disabled,
    ...(fiscal ? { codiceFiscale: fiscal } : {}),
    ...(status === 'created' && password ? { password } : {}),
    ...(resetLink && !staff && !disabled ? { resetLink } : {}),
  };
}

function resetBlock(resetLink) {
  if (!resetLink) return { html: '', text: '' };
  const href = escapeHtml(resetLink);
  return {
    html: `<p style="margin:16px 0;"><a href="${href}" style="display:inline-block;background:#32448C;color:#ffffff;text-decoration:none;padding:12px 18px;border-radius:8px;font-weight:700;">Imposta una nuova password</a></p>
<p style="font-size:13px;color:#444;word-break:break-all;">Se il pulsante non si apre: ${href}</p>`,
    text: `Per impostare una nuova password:\n${resetLink}\n`,
  };
}

function accountCopy({ status, to, password, resetLink, disabled, contactOnly }) {
  if (contactOnly) {
    return {
      html: '<p>La prenotazione resta collegata al suo account. Questa email è il recapito per le ricevute: l’email e la password di accesso restano invariate. Può cambiare la password da «Il mio account» sul sito.</p>',
      text: 'La prenotazione resta collegata al suo account. Questa email è il recapito per le ricevute: l’email e la password di accesso restano invariate. Può cambiare la password da «Il mio account» sul sito.\n',
    };
  }
  const safeTo = escapeHtml(to);
  if (status === 'created' && password) {
    const reset = resetBlock(resetLink);
    return {
      html: `<p>Le abbiamo creato un account cliente con questa email e lo abbiamo collegato alla prenotazione.</p>
<p style="margin:0 0 4px;">Email</p>
<p style="font-family:Consolas,Menlo,monospace;font-size:16px;margin:0 0 12px;">${safeTo}</p>
<p style="margin:0 0 4px;">Password temporanea</p>
<p style="font-family:Consolas,Menlo,monospace;font-size:24px;font-weight:700;letter-spacing:1px;color:#32448C;margin:0 0 8px;">${escapeHtml(password)}</p>
<p>La password è temporanea e casuale: non è il codice fiscale. Entri in <b>Area personale</b> del sito per vedere le sue prenotazioni e la cambi al primo accesso. Non la inoltri. L'area staff è riservata al personale.</p>
${reset.html}`,
      text: `Le abbiamo creato un account cliente con questa email e lo abbiamo collegato alla prenotazione.
Email: ${to}
Password temporanea: ${password}
La password è temporanea e casuale: non è il codice fiscale. Entri in Area personale del sito per vedere le sue prenotazioni e la cambi al primo accesso. Non la inoltri. L'area staff è riservata al personale.
${reset.text}`,
    };
  }
  if (status === 'existing' && disabled) {
    return {
      html: '<p>Risulta già un account con questa email, ma è disattivato. Non ne abbiamo creato un altro. La prenotazione resta valida: per l\'accesso contatti la farmacia.</p>',
      text: 'Risulta già un account con questa email, ma è disattivato. Non ne abbiamo creato un altro. La prenotazione resta valida: per l\'accesso contatti la farmacia.\n',
    };
  }
  if (status === 'existing') {
    const reset = resetBlock(resetLink);
    return {
      html: `<p>Esiste già un account con questa email: non ne abbiamo creato un altro e abbiamo collegato questa prenotazione a quell'account.</p>
<p>Se ricorda la password può continuare a usarla. Se non la ricorda, ne imposti una nuova dal link qui sotto.</p>
${reset.html}`,
      text: `Esiste già un account con questa email: non ne abbiamo creato un altro e abbiamo collegato questa prenotazione a quell'account.
Se ricorda la password può continuare a usarla. Se non la ricorda, ne imposti una nuova dal link.
${reset.text}`,
    };
  }
  if (status === 'staff') {
    return {
      html: '<p>La prenotazione è collegata a questa email. Si tratta di un account del personale: non abbiamo creato un nuovo utente e non abbiamo modificato la password.</p>',
      text: 'La prenotazione è collegata a questa email. Si tratta di un account del personale: non abbiamo creato un nuovo utente e non abbiamo modificato la password.\n',
    };
  }
  return { html: '', text: '' };
}

/** Ricevuta + eventuale blocco credenziali. La password entra solo se status è `created`. */
export function buildConfirmation({ nome, codice, servizio, quando, to, account = {}, codiceFiscale }) {
  const status = account.status;
  const password = status === 'created' ? account.password : undefined;
  const resetLink = (status === 'created' || status === 'existing') && !account.disabled ? account.resetLink : undefined;
  const who = plain(nome, 100) || 'cliente';
  const code = plain(codice, 12);
  const service = plain(servizio, 120) || 'Servizio';
  const when = plain(quando, 80);
  const cf = isValidCodiceFiscale(codiceFiscale) ? normalizeCodiceFiscale(codiceFiscale) : '';
  const extra = accountCopy({ status, to, password, resetLink, disabled: Boolean(account.disabled), contactOnly: Boolean(account.contactOnly) });
  const subject = `Conferma prenotazione ${code} – Farmacia San Ciro`;
  const html = `<!DOCTYPE html>
<html lang="it">
<head><meta charset="utf-8"><title>${escapeHtml(subject)}</title></head>
<body style="margin:0;padding:0;background:#f4f6fb;color:#1c1c1c;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.45;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Codice ${escapeHtml(code)}. ${escapeHtml(service)}. ${escapeHtml(when)}</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6fb;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;padding:28px 24px;">
        <tr><td>
          <p style="margin:0 0 4px;color:#32448C;font-size:13px;font-weight:700;letter-spacing:.04em;">FARMACIA SAN CIRO</p>
          <h1 style="margin:0 0 12px;font-size:22px;line-height:1.3;color:#32448C;">Prenotazione confermata</h1>
          <p>Gentile ${escapeHtml(who)},</p>
          <p>la sua prenotazione presso la <strong>Farmacia San Ciro</strong> è confermata. Questa email è la ricevuta.</p>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:12px 0 16px;background:#f4f6fb;border-radius:8px;">
            <tr><td style="padding:12px 14px;">
              <p style="margin:0 0 6px;">Servizio: <strong>${escapeHtml(service)}</strong></p>
              <p style="margin:0 0 6px;">Data e ora: <strong>${escapeHtml(when)}</strong></p>
              <p style="margin:0 0 6px;">Codice prenotazione: <strong style="font-size:22px;letter-spacing:2px;color:#32448C;">${escapeHtml(code)}</strong></p>
              ${cf ? `<p style="margin:0;">Codice fiscale: <strong>${escapeHtml(cf)}</strong></p>` : ''}
            </td></tr>
          </table>
          <p>Mostri il codice in farmacia. Per modifiche o disdette contatti la farmacia rispondendo a questa email oppure al telefono.</p>
          ${extra.html}
          <p style="margin-top:20px;font-size:13px;color:#555;">Farmacia San Ciro · Via Giacinto de Sivo 1, 80124 Napoli · 081 570 4733</p>
          <p style="font-size:13px;color:#555;">Se non ha richiesto questa prenotazione, ignori l'eventuale link per la password e risponda a questo messaggio.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  const text = `Farmacia San Ciro — prenotazione confermata

Gentile ${who},
la sua prenotazione è confermata. Questa email è la ricevuta.

Servizio: ${service}
Data e ora: ${when}
Codice prenotazione: ${code}
${cf ? `Codice fiscale: ${cf}` : ''}

Mostri il codice in farmacia. Per modifiche o disdette contatti la farmacia.

${extra.text}
Farmacia San Ciro · Via Giacinto de Sivo 1, 80124 Napoli · 081 570 4733
Se non ha richiesto questa prenotazione, ignori l'eventuale link per la password e risponda a questo messaggio.
`;
  return { subject, html, text };
}

export function idempotencyKey(appointmentId, codice, status) {
  const id = plain(appointmentId || codice || 'senza-id', 120).replace(/\s+/g, '');
  const state = plain(status || 'receipt', 40).replace(/\s+/g, '');
  return `booking-receipt/${id}/${state}`.slice(0, 256);
}

/** Invio Resend con chiave di idempotenza. 409 = stessa richiesta già accettata. Non registra il corpo. */
export async function sendReceipt({ fetchImpl, apiKey, payload, idempotencyKey: key, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) }) {
  const init = {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': key,
    },
    body: JSON.stringify(payload),
  };
  let status = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetchImpl('https://api.resend.com/emails', init);
      status = response.status;
      await response.text().catch(() => '');
      if (response.ok || response.status === 409) return { ok: true, status: response.status };
      if (response.status !== 429 && response.status < 500) return { ok: false, status: response.status };
    } catch {
      status = 0;
    }
    if (attempt < 2) await sleep(200 * (attempt + 1));
  }
  return { ok: false, status };
}

export function readEnv(name) {
  const fromNetlify = globalThis.Netlify?.env?.get?.(name);
  if (fromNetlify != null && fromNetlify !== '') return fromNetlify;
  const fromProcess = process.env[name];
  if (fromProcess == null || fromProcess === '') return undefined;
  return fromProcess;
}

export { safeAuthCode };
