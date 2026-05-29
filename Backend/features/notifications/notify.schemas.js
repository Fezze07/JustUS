const { z } = require("zod");

const notifySchema = z.object({
  title: z.string().min(1).max(120),
  body: z.string().min(1).max(500),
  receiverId: z.number().int().positive().optional(),
});

const paramsSchema = z.object({
  type: z.string().optional(),
});

module.exports = {
  notifySchema,
  paramsSchema,
};
