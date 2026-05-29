const {
  sendNotification,
  getPartnerId,
  adminSupabase,
  AppError,
  logNotification,
} = require("../../all_imports");

async function resolveNotificationTarget(type, body, senderId) {
  if (!senderId) {
    throw new AppError({ errorKey: "AUTH_FAIL_001", message: "Profilo mittente non trovato" });
  }

  const partnerId = await getPartnerId(senderId);
  const { title, body: content, receiverId } = body;

  if (type === "partner") {
    if (!partnerId) {
      throw new AppError({ errorKey: "API_VALIDATION_001", message: "Partner non trovato" });
    }

    return { receiverId: partnerId, title, body: content };
  }

  if (!receiverId) {
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "ID destinatario mancante" });
  }

  if (partnerId && Number(receiverId) !== Number(partnerId)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Destinatario non autorizzato" });
  }

  return { receiverId, title, body: content };
}

async function dispatchNotification({ type, senderId, payload }) {
  const target = await resolveNotificationTarget(type, payload, senderId);
  const deviceToken = await getReceiverDeviceToken(target.receiverId);

  await sendNotification(deviceToken, target.title, target.body, { type, senderId });
  await logNotification({ user_id: target.receiverId, type, status: "sent" });

  return { success: true };
}

/**
 * Recupera l'ultimo token del dispositivo registrato per un utente.
 * @param {string} userId - L'ID dell'utente di cui recuperare il token.
 * @returns {Promise<string>} Il token del dispositivo o lo User-Agent come fallback.
 * @throws {AppError} Se l'utente non viene trovato o non ha dispositivi registrati.
 */
async function getReceiverDeviceToken(userId) {
  const { data: rows, error } = await adminSupabase
    .from("user_devices")
    .select("device_token, user_agent")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  const token = rows?.device_token || rows?.user_agent;
  if (error || !rows || !token) {
    throw new AppError({ errorKey: "DB_NOT_FOUND_001", message: "Destinatario non trovato o senza token valido" });
  }

  return token;
}

module.exports = {
  dispatchNotification,
  resolveNotificationTarget,
  getReceiverDeviceToken,
};
