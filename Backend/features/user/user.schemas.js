const { z } = require("zod");

const userActionSchema = z.object({
  action: z.enum([
    "logout",
    "delete_account",
    "update_device_token",
    "refresh_session",
    "init_sync",
  ]),
  payload: z.record(z.any()).optional(),
});

module.exports = {
  userActionSchema,
};
