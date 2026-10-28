const { adminSupabase, AppError } = require("../../all_imports");
const { sendNotificationToUser } = require("../notifications/notification.service");
const { deleteObjectsByPrefix } = require("../media/r2.service");

async function deletePartnershipMedia(user1Id, user2Id) {
  const targets = [user1Id, user2Id].filter(Boolean);
  for (const uid of targets) {
    const prefix = `uploads/${uid}/`;
    try {
      await deleteObjectsByPrefix(prefix);
    } catch (err) {
      console.error("[partnership] Failed to delete media for user", uid, err?.message || err);
    }
  }
}

async function acceptPartnershipCancellation({ partnershipId, actorId }) {
  const { data: row, error: loadErr } = await adminSupabase
    .from("partnerships")
    .select("id, user_id_1, user_id_2, status, cancel_requested_by, cancel_expires_at")
    .eq("id", partnershipId)
    .maybeSingle();

  if (loadErr || !row) throw new AppError({ errorKey: "API_VALIDATION_012" });

  if (row.status !== "cancelled") throw new AppError({ errorKey: "API_VALIDATION_012" });
  const isMember = row.user_id_1 === actorId || row.user_id_2 === actorId;
  if (!isMember) throw new AppError({ errorKey: "API_VALIDATION_012" });
  if (row.cancel_requested_by === actorId) throw new AppError({ errorKey: "API_VALIDATION_012" });
  if (row.cancel_expires_at && new Date(row.cancel_expires_at) <= new Date()) {
    try {
      await adminSupabase.rpc("partnership_expire_cancellations");
    } catch (_) { /* best-effort expiry; the request is rejected either way */ }
    throw new AppError({ errorKey: "API_VALIDATION_014" });
  }

  const requesterId = row.cancel_requested_by;
  const user1 = row.user_id_1;
  const user2 = row.user_id_2;

  const { error: rpcErr } = await adminSupabase.rpc("partnership_cancel_accept", {
    p_partnership_id: partnershipId,
    p_actor_id: actorId,
  });
  if (rpcErr) {
    const msg = (rpcErr.message || "").toLowerCase();
    if (msg.includes("api-validation-014")) throw new AppError({ errorKey: "API_VALIDATION_014" });
    if (msg.includes("api-validation-012")) throw new AppError({ errorKey: "API_VALIDATION_012" });
    throw rpcErr;
  }

  await deletePartnershipMedia(user1, user2);

  if (requesterId) {
    try {
      await sendNotificationToUser({
        userId: requesterId,
        type: "partner",
        title: "cancellationAccepted",
        body: "cancellationAccepted",
      });
    } catch (e) {
      console.error("[partnership] Failed to send cancellationAccepted notification", e?.message || e);
    }
  }

  return { success: true };
}

module.exports = { acceptPartnershipCancellation, deletePartnershipMedia };
