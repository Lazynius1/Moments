const b = require('../bootstrap');
const { onDocumentCreated, admin } = b;

const DEFAULT_MINIMUM_ACCOUNT_AGE = 16;
const LEGACY_REGISTRATION_CUTOFF = new Date('2026-09-16T00:00:00.000Z');
const REGISTRATION_COMPLIANCE_FIELDS = [
  'privacyPolicyAccepted',
  'privacyPolicyAcceptedAt',
  'privacyPolicyVersion',
  'birthDate',
  'countryCode',
];

function minimumAgeForCountry(countryCode) {
  return String(countryCode || 'ZZ').toUpperCase() === 'IN' ? 18 : DEFAULT_MINIMUM_ACCOUNT_AGE;
}

function ageYearsFromBirthDate(birthDate, referenceDate = new Date()) {
  const born = birthDate.toDate ? birthDate.toDate() : new Date(birthDate);
  let years = referenceDate.getFullYear() - born.getFullYear();
  const monthDelta = referenceDate.getMonth() - born.getMonth();
  if (monthDelta < 0 || (monthDelta === 0 && referenceDate.getDate() < born.getDate())) {
    years -= 1;
  }
  return years;
}

function isLegacyRegistration(data, referenceDate = new Date()) {
  return Boolean(data)
    && referenceDate < LEGACY_REGISTRATION_CUTOFF
    && REGISTRATION_COMPLIANCE_FIELDS.every(
      (field) => !Object.prototype.hasOwnProperty.call(data, field)
    );
}

function isRegistrationCompliant(data, referenceDate = new Date()) {
  if (isLegacyRegistration(data, referenceDate)) return true;
  if (!data || data.privacyPolicyAccepted !== true) return false;
  if (!data.birthDate) return false;
  const countryCode = String(data.countryCode || '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(countryCode)) return false;
  if (typeof data.privacyPolicyVersion !== 'string' || data.privacyPolicyVersion.length === 0) {
    return false;
  }
  return ageYearsFromBirthDate(data.birthDate) >= minimumAgeForCountry(countryCode);
}

async function rollbackInvalidRegistration(db, userId, username) {
  const batch = db.batch();
  batch.delete(db.collection('users').doc(userId));
  if (username) {
    batch.delete(db.collection('usernames').doc(String(username).toLowerCase()));
  }
  await batch.commit().catch(() => {});

  try {
    await admin.auth().deleteUser(userId);
  } catch (error) {
    if (error?.code === 'auth/user-not-found') {
      return;
    }
    console.warn(`onUserRegistrationCompliance: auth delete failed for ${userId}`, error);
  }
}

/** Refuerzo server-side: borra cuentas que no cumplan age gate 16+ o consentimiento. */
const onUserRegistrationCompliance = onDocumentCreated('users/{userId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const userId = event.params.userId;
  const data = snap.data();

  const registrationDate = event.time ? new Date(event.time) : new Date();
  if (isRegistrationCompliant(data, registrationDate)) {
    return;
  }

  console.warn(`Rejecting non-compliant registration for ${userId}`);
  await rollbackInvalidRegistration(admin.firestore(), userId, data.username);
});

module.exports = {
  onUserRegistrationCompliance,
};
