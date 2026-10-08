/**
 * sendAccountEmail: envía con Resend los correos de cuenta (verificar email y restablecer contraseña)
 * con las plantillas propias en el idioma de la app. El enlace lo sigue generando Firebase Auth;
 * aquí solo se cambia el aspecto del correo y la página de destino (momentsapp.app/auth).
 *
 * - kind 'verify': requiere sesión; se envía al email de la cuenta autenticada.
 * - kind 'reset': sin sesión; nunca revela si el email tiene cuenta (responde igual en ambos casos).
 */

const { defineSecret } = require('firebase-functions/params');
const b = require('../bootstrap');
const { render, resolveLocale } = require('../helpers/account-email-templates');

const { HttpsError, onCall, admin, crypto } = b;

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');
const FROM = 'Moments <noreply@momentsapp.app>';
const ACTION_URL = 'https://momentsapp.app/auth';
const EMAIL_MAX_LENGTH = 320;
const NAME_MAX_LENGTH = 40;
const HOUR_MS = 60 * 60 * 1000;

const sha = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');

function clientIp(request) {
  const raw = request.rawRequest || {};
  const forwarded = String((raw.headers && raw.headers['x-forwarded-for']) || '').split(',')[0].trim();
  return forwarded || raw.ip || 'unknown';
}

/** Ventana fija en `authLookupRateLimits` (mismo esquema y TTL que http-auth-lookup). */
async function withinLimit(key, max, windowMs) {
  const db = admin.firestore();
  const ref = db.doc(`authLookupRateLimits/${key}`);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const windowStart = snap.exists ? Number(snap.get('windowStart')) : 0;
    const count = snap.exists ? Number(snap.get('count')) : 0;
    const inWindow = Number.isFinite(windowStart) && now - windowStart < windowMs;
    if (inWindow && count >= max) return false;
    tx.set(ref, {
      windowStart: inWindow ? windowStart : now,
      count: inWindow ? count + 1 : 1,
      expireAt: admin.firestore.Timestamp.fromMillis(now + windowMs * 2)
    });
    return true;
  });
}

async function displayNameFor(uid, fallback) {
  const clean = (value) => String(value || '').replace(/[\r\n\t]/g, ' ').trim().slice(0, NAME_MAX_LENGTH);
  if (fallback) return clean(fallback);
  try {
    const snap = await admin.firestore().doc(`users/${uid}`).get();
    return clean(snap.get('username'));
  } catch {
    return '';
  }
}

/** Lleva el oobCode del enlace de Firebase a la página propia, conservando el idioma. */
function actionLink(firebaseLink, mode, locale) {
  const oobCode = new URL(firebaseLink).searchParams.get('oobCode');
  if (!oobCode) throw new Error('Firebase action link without oobCode');
  const url = new URL(ACTION_URL);
  url.searchParams.set('mode', mode);
  url.searchParams.set('oobCode', oobCode);
  url.searchParams.set('lang', locale);
  return url.toString();
}

async function deliver({ kind, to, name, link, locale }) {
  const { subject, html, text } = render({ kind, locale, name, email: to, link });
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY.value()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: FROM,
      to: [to],
      subject,
      html,
      text,
      tags: [{ name: 'kind', value: kind }, { name: 'locale', value: locale.replace(/[^A-Za-z0-9_-]/g, '_') }]
    })
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    console.error(`[sendAccountEmail] Resend ${response.status}: ${detail.slice(0, 300)}`);
    throw new HttpsError('unavailable', 'Email provider error');
  }
}

const sendAccountEmail = onCall({ secrets: [RESEND_API_KEY], timeoutSeconds: 20 }, async (request) => {
  const data = request.data || {};
  const kind = data.kind;
  const locale = resolveLocale(data.locale);

  if (kind === 'verify') {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');

    const user = await admin.auth().getUser(uid);
    if (!user.email) throw new HttpsError('failed-precondition', 'Account has no email');
    if (user.emailVerified) return { sent: false, alreadyVerified: true };

    if (!(await withinLimit(`sendAccountEmail_verify_${uid}`, 5, HOUR_MS))) {
      throw new HttpsError('resource-exhausted', 'Too many emails, try again later');
    }

    const firebaseLink = await admin.auth().generateEmailVerificationLink(user.email);
    const name = await displayNameFor(uid, data.name);
    await deliver({ kind, to: user.email, name, link: actionLink(firebaseLink, 'verifyEmail', locale), locale });
    return { sent: true };
  }

  if (kind === 'reset') {
    const email = String(data.email || '').trim().toLowerCase();
    if (!email || email.length > EMAIL_MAX_LENGTH || !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'Invalid email');
    }

    const [ipOk, emailOk] = await Promise.all([
      withinLimit(`sendAccountEmail_ip_${sha(clientIp(request))}`, 20, HOUR_MS),
      withinLimit(`sendAccountEmail_reset_${sha(email)}`, 5, HOUR_MS)
    ]);
    if (!ipOk || !emailOk) throw new HttpsError('resource-exhausted', 'Too many emails, try again later');

    let user;
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch (error) {
      // Misma respuesta exista o no la cuenta: no se puede usar para averiguar emails registrados.
      if (error.code === 'auth/user-not-found') return { sent: true };
      if (error.code === 'auth/invalid-email') throw new HttpsError('invalid-argument', 'Invalid email');
      throw error;
    }
    if (user.disabled) return { sent: true };

    const firebaseLink = await admin.auth().generatePasswordResetLink(user.email);
    const name = await displayNameFor(user.uid, '');
    await deliver({ kind, to: user.email, name, link: actionLink(firebaseLink, 'resetPassword', locale), locale });
    return { sent: true };
  }

  throw new HttpsError('invalid-argument', 'Unknown email kind');
});

module.exports = { sendAccountEmail };
