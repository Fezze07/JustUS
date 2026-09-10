const admin = require("firebase-admin");
const { getMessaging } = require("firebase-admin/messaging");
let initialized = false;

function initializeFirebaseAdmin() {
  if (admin.apps?.length) {
    initialized = true;
    return true;
  }
  const serviceAccountPath = process.env.FCM_SERVICE_ACCOUNT_PATH;

  if (!serviceAccountPath) {
    console.error("[FCM] FCM_SERVICE_ACCOUNT_PATH is not configured");
    return false;
  }

  let serviceAccount;

  try {
    serviceAccount = require(serviceAccountPath);
  } catch (err) {
    console.error("[FCM] Error loading Firebase service account:", err.message);
    return false;
  }

  if (!serviceAccount || !admin.cert) {
    console.error("[FCM] Invalid service account object or admin.cert missing");
    return false;
  }

  try {
    admin.initializeApp({
      credential: admin.cert(serviceAccount),
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
  return getMessaging();
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
