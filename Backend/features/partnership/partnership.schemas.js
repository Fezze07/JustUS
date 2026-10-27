const { z } = require("zod");

const acceptCancelSchema = z.object({
  partnershipId: z.coerce.number().int().positive(),
});

module.exports = { acceptCancelSchema };
