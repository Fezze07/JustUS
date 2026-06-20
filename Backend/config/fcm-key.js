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
  } catch (err) {
    console.error("[FCM] Error loading secrets/fcm-key.json:", err.message);
    return false;
  }

  if (!serviceAccount || !admin.credential?.cert) {
    console.error("[FCM] Invalid service account object or credential.cert missing");
    return false;
  }

  try {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    initialized = true;
    return true;
  } catch (err) {
    console.error("[FCM] Error initializing firebase-admin app:", err.message);
    return false;
  }
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
