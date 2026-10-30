const {
  getPartnerId,
  getCancellationPartnerId,
  adminSupabase,
  AppError,
  assertDbSuccess,
  logNotification,
} = require("../../all_imports");
const {
  normalizeDataPayload,
  safeLogInfo,
  deliverToBatches,
} = require("./notification.utils");

const FCM_DEVICE_TYPES = new Set(["android", "ios", "web"]);

async function safeLogNotification(record) {
  if (typeof logNotification === "function") {
    await logNotification(record);
  }
}

function isDeliverableDevice(device) {
  const installationId = device?.installation_id;
  if (!installationId) return false;

  const type = device.device_type?.toLowerCase();
  return !type || FCM_DEVICE_TYPES.has(type);
}

async function fetchUserDevices(userId) {
  const rows = assertDbSuccess(
    await adminSupabase
      .from("user_devices")
      .select("id, installation_id, device_type, locale")
      .eq("user_id", userId)
      .not("installation_id", "is", null),
    "DB_READ_001"
  );

  return rows.filter(isDeliverableDevice);
}

async function deleteInvalidInstallations(userId, fids) {
  const uniqueFids = [...new Set(fids.filter(Boolean))];
  if (uniqueFids.length === 0) return 0;

  assertDbSuccess(
    await adminSupabase
      .from("user_devices")
      .delete()
      .eq("user_id", userId)
      .in("installation_id", uniqueFids),
    "DB_WRITE_001"
  );

  return uniqueFids.length;
}

async function sendNotificationToUser({ userId, type, title, data = {} }) {
  const devices = await fetchUserDevices(userId);
  const fids = [...new Set(devices.map((device) => device.installation_id))];

  if (fids.length === 0) {
    console.warn(`[notify] No devices for userId=${userId} type=${type} — installation id not registered`);
    await safeLogNotification({ user_id: userId, type, status: "no_devices" });
    return {
      success: true,
      delivered: 0,
      failed: 0,
      invalidInstallationsRemoved: 0,
      deviceCount: 0,
    };
  }

  const { delivered, failed, invalidFids, configured } = await deliverToBatches({
    userId,
    type,
    title,
    data,
    devices,
  });

  const invalidInstallationsRemoved = await deleteInvalidInstallations(userId, invalidFids);
  const status = configured
    ? (failed > 0 ? "partial" : "sent")
    : "skipped_firebase_not_configured";

  await safeLogNotification({ user_id: userId, type, status });
  await safeLogInfo("notification.delivery_summary", {
    user_id: userId,
    type,
    delivered,
    failed,
    invalid_installations_removed: invalidInstallationsRemoved,
  });

  return {
    success: delivered > 0 || (fids.length === 0 && failed === 0),
    delivered,
    failed,
    invalidInstallationsRemoved,
    deviceCount: fids.length,
    configured,
  };
}

async function resolveNotificationTarget(type, body, senderId) {
  if (!senderId) {
    throw new AppError({ errorKey: "AUTH_FAIL_001", message: "Sender profile not found" });
  }

  const partnerId = await getPartnerId(senderId);
  const { notificationKey, params, receiverId } = body;

  if (type === "partner") {
    let resolvedPartnerId = partnerId;
    if (!resolvedPartnerId && notificationKey === "cancellationRequested") {
      resolvedPartnerId = await getCancellationPartnerId(senderId);
    }
    if (!resolvedPartnerId) {
      throw new AppError({ errorKey: "API_VALIDATION_001", message: "Partner not found" });
    }

    return { receiverId: resolvedPartnerId, notificationKey, params };
  }

  if (!receiverId) {
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "Missing receiver ID" });
  }

  if (!partnerId || Number(receiverId) !== Number(partnerId)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Receiver not authorized" });
  }

  return { receiverId: partnerId, notificationKey, params };
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

async function getReceiverInstallationId(userId) {
  const devices = await fetchUserDevices(userId);
  const installationId = devices[0]?.installation_id;
  if (!installationId) {
    throw new AppError({ errorKey: "DB_NOT_FOUND_001", message: "Receiver not found or has no valid installation id" });
  }

  return installationId;
}

module.exports = {
  dispatchNotification,
  resolveNotificationTarget,
  getReceiverInstallationId,
  sendNotificationToUser,
  fetchUserDevices,
  deleteInvalidInstallations,
  normalizeDataPayload,
};
