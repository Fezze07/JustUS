const { z } = require("zod");

// `installationId` is the Firebase Installation ID (FID) used as the FCM
// direct-send target. The minimum length rejects the empty string some
// clients use when the platform has no FCM, which would otherwise create a
// single shared row on the globally UNIQUE installation_id column.
const updateInstallationSchema = z.object({
  installationId: z.string().min(16).max(512),
  deviceType: z.string().max(50).optional(),
  locale: z.string().max(10).optional(),
});

const revokeInstallationSchema = z.object({
  installationId: z.string().min(16).max(512),
});

const loginRiskSchema = z.object({
  email: z.string().email(),
  deviceFingerprint: z.string().min(12).max(128),
});

const loginAttemptSchema = loginRiskSchema.extend({
  reason: z.string().max(200).optional(),
});

const sessionBindSchema = z.object({
  deviceFingerprint: z.string().min(12).max(128),
});

const inviteSchema = z.object({
  email: z.string().email(),
  partnershipCode: z.string().length(6, "Il codice deve essere di 6 caratteri"),
});

// Account-only invite: the email address of a partner who has no JustUs
// account yet. `redirectTo` is forwarded to GoTrue, which validates it against
// the project's redirect allow-list.
const inviteUserSchema = z.object({
  email: z.string().email(),
  redirectTo: z.string().url().max(2048).optional(),
});

module.exports = {
  updateInstallationSchema,
  revokeInstallationSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionBindSchema,
  inviteSchema,
  inviteUserSchema,
};
