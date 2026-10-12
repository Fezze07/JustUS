const { z } = require("zod");

// The client's "no token" placeholder is a single shared string, and
// user_devices.device_token is globally UNIQUE, so accepting it would re-point
// one row between unrelated accounts. Reject it at the trust boundary.
const updateDeviceTokenSchema = z.object({
  deviceToken: z
    .string()
    .min(16)
    .max(512)
    .refine((t) => t !== "UNKNOWN_DEVICE_TOKEN", {
      message: "Placeholder device token is not registrable",
    }),
  deviceType: z.string().max(50).optional(),
  locale: z.string().max(10).optional(),
});

const revokeDeviceTokenSchema = z.object({
  deviceToken: z.string().min(16).max(512),
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

module.exports = {
  updateDeviceTokenSchema,
  revokeDeviceTokenSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionBindSchema,
  inviteSchema,
};
