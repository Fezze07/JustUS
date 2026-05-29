const { z } = require("zod");

const aiSchema = z.object({
  type: z.string().max(120).optional(),
});

module.exports = {
  aiSchema,
};
