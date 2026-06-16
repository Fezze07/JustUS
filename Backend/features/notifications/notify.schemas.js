const { z } = require("zod");

const notifySchema = z.object({
  notificationKey: z.string().min(1).max(80),
  params: z.record(z.string()).optional(),
  receiverId: z.number().int().positive().optional(),
});

const paramsSchema = z.object({
  type: z.string().optional(),
});

module.exports = {
  notifySchema,
  paramsSchema,
};
