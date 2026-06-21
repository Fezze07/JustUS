const { z } = require("zod");

const updateDeviceTokenSchema = z.object({
  deviceToken: z.string().min(16).max(512),
  deviceType: z.string().max(50).optional(),
  locale: z.string().max(10).optional(),
});

const loginRiskSchema = z.object({
  email: z.string().email(),
  deviceFingerprint: z.string().min(12).max(128),
});

const loginAttemptSchema = loginRiskSchema.extend({
  reason: z.string().max(200).optional(),
});

const sessionSyncSchema = z.object({
  deviceFingerprint: z.string().min(12).max(128),
  deviceLabel: z.string().min(2).max(120),
});

const inviteSchema = z.object({
  email: z.string().email(),
  partnershipCode: z.string().length(6, "Il codice deve essere di 6 caratteri"),
});

const refreshTokenSchema = z.object({
  refreshToken: z.string().min(20).max(1024),
});

module.exports = {
  updateDeviceTokenSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionSyncSchema,
  inviteSchema,
  refreshTokenSchema,
};
