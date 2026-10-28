const { z } = require("zod");

const notifySchema = z.object({
  notificationKey: z.string().min(1).max(80),
  params: z.record(z.string()).optional(),
  receiverId: z.number().int().positive().optional(),
});

module.exports = {
  notifySchema,
};
