const b = require('../bootstrap');
const { onDocumentCreated, admin } = b;

const DEFAULT_MINIMUM_ACCOUNT_AGE = 16;

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

function isRegistrationCompliant(data) {
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
    console.warn(`onUserRegistrationCompliance: auth delete failed for ${userId}`, error);
  }
}

/** Refuerzo server-side: borra cuentas que no cumplan age gate 16+ o consentimiento. */
const onUserRegistrationCompliance = onDocumentCreated('users/{userId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const userId = event.params.userId;
  const data = snap.data();

  if (isRegistrationCompliant(data)) {
    return;
  }

  console.warn(`Rejecting non-compliant registration for ${userId}`);
  await rollbackInvalidRegistration(admin.firestore(), userId, data.username);
});

module.exports = {
  onUserRegistrationCompliance,
};
