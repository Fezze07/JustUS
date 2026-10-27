const { sendMulticastNotification, logInfo, serializeError } = require("../../all_imports");

const FCM_BATCH_SIZE = 500;
const INVALID_FID_CODES = new Set([
  "messaging/invalid-recipient",
  "messaging/installation-id-not-registered",
]);

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
      body: `${p.partnerName || "Il tuo partner"} ha accettato la tua richiesta`,
    }),
    cancellationRequested: (p) => ({
      title: "Richiesta di interruzione",
      body: `${p.partnerName || "Il tuo partner"} ha chiesto di interrompere la partnership`,
    }),
    cancellationDeclined: (p) => ({
      title: "Richiesta di interruzione rifiutata",
      body: `${p.partnerName || "Il tuo partner"} ha rifiutato la richiesta di interruzione`,
    }),
    cancellationAccepted: (p) => ({
      title: "Partnership interrotta",
      body: `${p.partnerName || "Il tuo partner"} ha accettato la richiesta di interruzione`,
    }),
    missyou: (p) => ({
      title: "Mi manchi",
      body: `${p.partnerName || "Il tuo partner"} sente la tua mancanza`,
    }),
    moodUpdated: (p) => ({
      title: "Nuovo Umore",
      body: `${p.partnerName || "Il tuo partner"} ha aggiornato il suo umore`,
    }),
    answerSubmitted: (p) => ({
      title: "Nuova Risposta",
      body: `${p.partnerName || "Il tuo partner"} ha risposto alla domanda`,
    }),
    newQuestion: () => ({
      title: "Nuova Domanda di Coppia",
      body: "Una nuova domanda ti aspetta!",
    }),
    driveItemAdded: (p) => ({
      title: "Nuovo Ricordo Aggiunto",
      body: `${p.partnerName || "Il tuo partner"} ha aggiunto un ricordo`,
    }),
    reactionAdded: (p) => ({
      title: "Nuova Reazione a un Ricordo",
      body: `${p.partnerName || "Il tuo partner"} ha reagito con ${p.emojiChar || "❤️"}`,
    }),
    bucketItemAdded: (p) => ({
      title: "Nuovo Desiderio nella Lista",
      body: `${p.partnerName || "Il tuo partner"} ha aggiunto un desiderio`,
    }),
    default: () => ({
      title: "JustUS",
      body: "Hai una nuova notifica",
    }),
  },
  en: {
    requestAccepted: (p) => ({
      title: "Request Accepted",
      body: `${p.partnerName || "Your partner"} accepted your request`,
    }),
    cancellationRequested: (p) => ({
      title: "Cancellation Request",
      body: `${p.partnerName || "Your partner"} asked to end the partnership`,
    }),
    cancellationDeclined: (p) => ({
      title: "Cancellation Declined",
      body: `${p.partnerName || "Your partner"} declined the cancellation request`,
    }),
    cancellationAccepted: (p) => ({
      title: "Partnership Ended",
      body: `${p.partnerName || "Your partner"} accepted the cancellation request`,
    }),
    missyou: (p) => ({
      title: "Miss You",
      body: `${p.partnerName || "Your partner"} misses you`,
    }),
    moodUpdated: (p) => ({
      title: "New Mood",
      body: `${p.partnerName || "Your partner"} updated their mood`,
    }),
    answerSubmitted: (p) => ({
      title: "New Answer",
      body: `${p.partnerName || "Your partner"} answered the question`,
    }),
    newQuestion: () => ({
      title: "New Couple Question",
      body: "A new question awaits you!",
    }),
    driveItemAdded: (p) => ({
      title: "New Memory Added",
      body: `${p.partnerName || "Your partner"} added a memory`,
    }),
    reactionAdded: (p) => ({
      title: "New Reaction to a Memory",
      body: `${p.partnerName || "Your partner"} reacted with ${p.emojiChar || "❤️"}`,
    }),
    bucketItemAdded: (p) => ({
      title: "New Wish in the Bucket List",
      body: `${p.partnerName || "Your partner"} added a wish`,
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

  const localizedFn = lang[key] || lang.default;
  return localizedFn(params);
}

// fids = Firebase Installation IDs; sendEachForMulticast requires this exact field
function buildFcmMessage({ fids, type, title, data, locale = "en" }) {
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
    fids,
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

function collectInvalidFids(batchFids, responses = []) {
  const invalidFids = [];

  responses.forEach((response, index) => {
    const code = response.error?.code;
    if (INVALID_FID_CODES.has(code)) {
      invalidFids.push(batchFids[index]);
    }
  });

  return invalidFids;
}

// Group devices by locale (S1)
function groupByLocale(devices) {
  const devicesByLocale = {};
  for (const device of devices) {
    const locale = device.locale || "en";
    if (!devicesByLocale[locale]) {
      devicesByLocale[locale] = [];
    }
    devicesByLocale[locale].push(device.installation_id);
  }
  return devicesByLocale;
}

async function sendBatchWithRetry({ userId, type, title, data, locale, batchFids }) {
  const maxAttempts = 3;
  for (let attempts = 1; attempts <= maxAttempts; attempts++) {
    try {
      const fidPreview = process.env.NODE_ENV === "production" ? "" : ` — fids: ${batchFids.map(f => f.slice(0, 12) + '…').join(', ')}`;
      console.log(`[notify] Sending FCM to ${batchFids.length} installation id(s) for userId=${userId} type=${type} locale=${locale} (attempt ${attempts})${fidPreview}`);
      return await sendMulticastNotification(buildFcmMessage({ fids: batchFids, type, title, data, locale }));
    } catch (error) {
      // Retry only transient failures; invalid-FID errors surface immediately to the caller
      const isTransient = !error.code || !INVALID_FID_CODES.has(error.code);
      if (!isTransient || attempts === maxAttempts) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, 500 * attempts));
    }
  }
}

function tallyBatchResponse(stats, batchFids, response) {
  stats.delivered += response.successCount ?? 0;
  stats.failed += response.failureCount ?? 0;

  // Log per-installation errors for diagnosis
  if (response.responses) {
    response.responses.forEach((r, i) => {
      if (r.error) {
        console.warn(`[notify] FCM fid[${i}] (${batchFids[i]?.slice(0, 12)}…) error: ${r.error.code} — ${r.error.message}`);
      }
    });
  }

  stats.invalidFids.push(...collectInvalidFids(batchFids, response.responses));
}

async function recordBatchFailure(stats, { userId, type, batchFids, error }) {
  stats.failed += batchFids.length;
  if (error.code && INVALID_FID_CODES.has(error.code)) {
    stats.invalidFids.push(...batchFids);
  }
  await safeLogInfo("notification.fcm_batch_failed", {
    user_id: userId,
    type,
    error: typeof serializeError === "function" ? serializeError(error) : error?.message,
  });
}

async function deliverToBatches({ userId, type, title, data, devices }) {
  const stats = { delivered: 0, failed: 0, invalidFids: [], configured: true };
  const devicesByLocale = groupByLocale(devices);

  localeLoop:
  for (const [locale, localeFids] of Object.entries(devicesByLocale)) {
    const uniqueLocaleFids = [...new Set(localeFids)];
    for (const batchFids of chunk(uniqueLocaleFids, FCM_BATCH_SIZE)) {
      try {
        const response = await sendBatchWithRetry({ userId, type, title, data, locale, batchFids });
        stats.configured = response.configured !== false;
        if (!stats.configured) {
          console.warn(`[notify] FCM is not configured — aborting further sends for userId=${userId}`);
          break localeLoop;
        }
        tallyBatchResponse(stats, batchFids, response);
      } catch (error) {
        await recordBatchFailure(stats, { userId, type, batchFids, error });
      }
    }
  }
  return stats;
}

module.exports = {
  normalizeDataPayload,
  safeLogInfo,
  deliverToBatches,
};
