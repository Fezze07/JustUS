const {
  sendMulticastNotification,
  getPartnerId,
  adminSupabase,
  AppError,
  assertDbSuccess,
  logInfo,
  logNotification,
  serializeError,
} = require("../../all_imports");

const FCM_BATCH_SIZE = 500;
const INVALID_FCM_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
  "messaging/invalid-recipient",
]);
const FCM_DEVICE_TYPES = new Set(["android", "ios", "web"]);

function normalizeDataPayload(data = {}) {
  return Object.entries(data).reduce((acc, [key, value]) => {
    if (value === undefined || value === null) return acc;
    acc[key] = typeof value === "string" ? value : JSON.stringify(value);
    return acc;
  }, {});
}

async function safeLogInfo(event, payload) {
  if (typeof logInfo === "function") {
    await logInfo(event, payload);
  }
}

async function safeLogNotification(record) {
  if (typeof logNotification === "function") {
    await logNotification(record);
  }
}

function isDeliverableDevice(device) {
  const token = device?.device_token;
  if (!token || token === "UNKNOWN_DEVICE_TOKEN") return false;

  const type = device.device_type?.toLowerCase();
  return !type || FCM_DEVICE_TYPES.has(type);
}

function chunk(values, size) {
  const chunks = [];
  for (let i = 0; i < values.length; i += size) {
    chunks.push(values.slice(i, i + size));
  }
  return chunks;
}

const LOCALIZATIONS = {
  it: {
    requestAccepted: (p) => ({
      title: "Richiesta Accettata",
      body: `${p.partnerName} ha accettato la tua richiesta`,
    }),
    missyou: (p) => ({
      title: "Mi manchi",
      body: `${p.partnerName} sente la tua mancanza`,
    }),
    moodUpdated: (p) => ({
      title: "Nuovo Umore",
      body: `${p.partnerName} ha aggiornato il suo umore`,
    }),
    answerSubmitted: (p) => ({
      title: "Nuova Risposta",
      body: `${p.partnerName} ha risposto alla domanda`,
    }),
    newQuestion: () => ({
      title: "Nuova Domanda di Coppia",
      body: "Una nuova domanda ti aspetta!",
    }),
    driveItemAdded: (p) => ({
      title: "Nuovo Ricordo Aggiunto",
      body: `${p.partnerName} ha aggiunto un ricordo`,
    }),
    reactionAdded: (p) => ({
      title: "Nuova Reazione a un Ricordo",
      body: `${p.partnerName} ha reagito con ${p.emojiChar}`,
    }),
    bucketItemAdded: (p) => ({
      title: "Nuovo Desiderio nella Lista",
      body: `${p.partnerName} ha aggiunto un desiderio`,
    }),
    default: () => ({
      title: "JustUS",
      body: "Hai una nuova notifica",
    }),
  },
  en: {
    requestAccepted: (p) => ({
      title: "Request Accepted",
      body: `${p.partnerName} accepted your request`,
    }),
    missyou: (p) => ({
      title: "Miss You",
      body: `${p.partnerName} misses you`,
    }),
    moodUpdated: (p) => ({
      title: "New Mood",
      body: `${p.partnerName} updated their mood`,
    }),
    answerSubmitted: (p) => ({
      title: "New Answer",
      body: `${p.partnerName} answered the question`,
    }),
    newQuestion: () => ({
      title: "New Couple Question",
      body: "A new question awaits you!",
    }),
    driveItemAdded: (p) => ({
      title: "New Memory Added",
      body: `${p.partnerName} added a memory`,
    }),
    reactionAdded: (p) => ({
      title: "New Reaction to a Memory",
      body: `${p.partnerName} reacted with ${p.emojiChar}`,
    }),
    bucketItemAdded: (p) => ({
      title: "New Wish in the Bucket List",
      body: `${p.partnerName} added a wish`,
    }),
    default: () => ({
      title: "JustUS",
      body: "You have a new notification",
    }),
  },
};

function localizeNotificationText(key, paramsInput = {}, locale = "en") {
  let params = paramsInput;
  if (typeof params === "string") {
    try {
      params = JSON.parse(params);
    } catch (_) {
      params = {};
    }
  }

  const langCode = LOCALIZATIONS[locale] ? locale : "en";
  const lang = LOCALIZATIONS[langCode];

  params.partnerName = params.partnerName || "Your partner";
  params.emojiChar = params.emojiChar || "❤️";

  const localizedFn = lang[key] || lang.default;
  return localizedFn(params);
}

function buildFcmMessage({ tokens, type, title, body, data, locale = "en" }) {
  const notificationKey = data?.notificationKey || title;
  const localized = localizeNotificationText(notificationKey, data?.params, locale);

  const payload = normalizeDataPayload({
    ...data,
    type,
    title: localized.title,
    body: localized.body,
    source: "justus-backend",
    notificationId: `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
  });

  return {
    tokens,
    notification: {
      title: localized.title,
      body: localized.body,
    },
    data: payload,
    android: {
      priority: "high",
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: {
            title: localized.title,
            body: localized.body,
          },
          sound: "default",
          badge: 1,
        },
      },
    },
    webpush: {
      notification: {
        title: localized.title,
        body: localized.body,
      },
      data: payload,
    },
  };
}

async function fetchUserDevices(userId) {
  const rows = assertDbSuccess(
    await adminSupabase
      .from("user_devices")
      .select("id, device_token, device_type, locale")
      .eq("user_id", userId)
      .not("device_token", "is", null),
    "DB_READ_001"
  );

  return rows.filter(isDeliverableDevice);
}

async function deleteInvalidTokens(tokens) {
  const uniqueTokens = [...new Set(tokens.filter(Boolean))];
  if (uniqueTokens.length === 0) return 0;

  assertDbSuccess(
    await adminSupabase
      .from("user_devices")
      .delete()
      .in("device_token", uniqueTokens),
    "DB_WRITE_001"
  );

  return uniqueTokens.length;
}

function collectInvalidTokens(batchTokens, responses = []) {
  const invalidTokens = [];

  responses.forEach((response, index) => {
    const code = response.error?.code;
    if (INVALID_FCM_TOKEN_CODES.has(code)) {
      invalidTokens.push(batchTokens[index]);
    }
  });

  return invalidTokens;
}

async function sendNotificationToUser({ userId, type, title, body, data = {} }) {
  const devices = await fetchUserDevices(userId);
  const tokens = [...new Set(devices.map((device) => device.device_token))];

  if (tokens.length === 0) {
    console.warn(`[notify] No devices for userId=${userId} type=${type} — token not registered`);
    await safeLogNotification({ user_id: userId, type, status: "no_devices" });
    return {
      success: true,
      delivered: 0,
      failed: 0,
      invalidTokensRemoved: 0,
      deviceCount: 0,
    };
  }

  // Determine receiver locale from their first device (fallback to "en")
  const receiverLocale = devices.find(d => d.locale)?.locale || "en";

  let delivered = 0;
  let failed = 0;
  const invalidTokens = [];
  let configured = true;

  for (const batchTokens of chunk(tokens, FCM_BATCH_SIZE)) {
    try {
      console.log(`[notify] Sending FCM to ${batchTokens.length} token(s) for userId=${userId} type=${type} locale=${receiverLocale} — tokens: ${batchTokens.map(t => t.slice(0, 12) + '\u2026').join(', ')}`);
      const response = await sendMulticastNotification(
        buildFcmMessage({ tokens: batchTokens, type, title, body, data, locale: receiverLocale })
      );

      configured = response.configured !== false;
      delivered += response.successCount ?? 0;
      failed += response.failureCount ?? 0;

      // Log per-token errors for diagnosis
      if (response.responses) {
        response.responses.forEach((r, i) => {
          if (r.error) {
            console.warn(`[notify] FCM token[${i}] (${batchTokens[i]?.slice(0, 12)}…) error: ${r.error.code} — ${r.error.message}`);
          }
        });
      }

      invalidTokens.push(...collectInvalidTokens(batchTokens, response.responses));
    } catch (error) {
      failed += batchTokens.length;
      await safeLogInfo("notification.fcm_batch_failed", {
        user_id: userId,
        type,
        error: typeof serializeError === "function" ? serializeError(error) : error?.message,
      });
    }
  }

  const invalidTokensRemoved = await deleteInvalidTokens(invalidTokens);
  const status = configured
    ? (failed > 0 ? "partial" : "sent")
    : "skipped_firebase_not_configured";

  await safeLogNotification({ user_id: userId, type, status });
  await safeLogInfo("notification.delivery_summary", {
    user_id: userId,
    type,
    delivered,
    failed,
    invalid_tokens_removed: invalidTokensRemoved,
  });

  return {
    success: true,
    delivered,
    failed,
    invalidTokensRemoved,
    deviceCount: tokens.length,
  };
}

async function sendNotificationToUsers({ userIds, type, title, body, data = {} }) {
  const uniqueUserIds = [...new Set(userIds.filter(Boolean).map(Number))];
  const results = [];

  for (const userId of uniqueUserIds) {
    results.push(await sendNotificationToUser({ userId, type, title, body, data }));
  }

  return {
    success: true,
    recipients: uniqueUserIds.length,
    results,
  };
}

async function resolveNotificationTarget(type, body, senderId) {
  if (!senderId) {
    throw new AppError({ errorKey: "AUTH_FAIL_001", message: "Profilo mittente non trovato" });
  }

  const partnerId = await getPartnerId(senderId);
  const { notificationKey, params, receiverId } = body;

  if (type === "partner") {
    if (!partnerId) {
      throw new AppError({ errorKey: "API_VALIDATION_001", message: "Partner non trovato" });
    }

    return { receiverId: partnerId, notificationKey, params };
  }

  if (!receiverId) {
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "ID destinatario mancante" });
  }

  if (partnerId && Number(receiverId) !== Number(partnerId)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Destinatario non autorizzato" });
  }

  return { receiverId, notificationKey, params };
}

async function dispatchNotification({ type, senderId, payload }) {
  const target = await resolveNotificationTarget(type, payload, senderId);

  return sendNotificationToUser({
    userId: target.receiverId,
    type,
    title: target.notificationKey,
    body: target.notificationKey,
    data: {
      senderId,
      notificationKey: target.notificationKey,
      ...(target.params && { params: target.params }),
    },
  });
}

async function getReceiverDeviceToken(userId) {
  const devices = await fetchUserDevices(userId);
  const token = devices[0]?.device_token;
  if (!token) {
    throw new AppError({ errorKey: "DB_NOT_FOUND_001", message: "Destinatario non trovato o senza token valido" });
  }

  return token;
}

module.exports = {
  dispatchNotification,
  resolveNotificationTarget,
  getReceiverDeviceToken,
  sendNotificationToUser,
  sendNotificationToUsers,
  fetchUserDevices,
  deleteInvalidTokens,
  normalizeDataPayload,
};
