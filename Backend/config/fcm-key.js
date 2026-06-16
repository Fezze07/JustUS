const admin = require("firebase-admin");
const path = require("path");

let initialized = false;

function initializeFirebaseAdmin() {
  if (admin.apps?.length) {
    initialized = true;
    return true;
  }

  let serviceAccount;
  try {
    serviceAccount = require(path.join(__dirname, "..", "secrets", "fcm-key.json"));
  } catch (_) {
    return false;
  }

  if (!serviceAccount || !admin.credential?.cert) return false;

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  initialized = true;
  return true;
}

function getMessagingClient() {
  if (!initialized && !initializeFirebaseAdmin()) return null;
  return admin.messaging();
}

async function sendMulticastNotification(message, dryRun = false) {
  const messaging = getMessagingClient();
  if (!messaging) {
    return {
      configured: false,
      successCount: 0,
      failureCount: 0,
      responses: [],
    };
  }

  const response = await messaging.sendEachForMulticast(message, dryRun);
  return { configured: true, ...response };
}

module.exports = {
  initializeFirebaseAdmin,
  sendMulticastNotification,
};
