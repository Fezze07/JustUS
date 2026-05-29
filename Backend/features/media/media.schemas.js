const { z } = require("zod");

const presignSchema = z.object({
  type: z.enum(["image", "video", "audio", "file"]),
  filename: z.string().min(1).max(255),
  mimeType: z.string().min(3).max(128),
  size: z.number().int().positive(),
  folder: z.string().min(1).max(32).optional(),
});

const completeSchema = z.object({
  kind: z.enum(["drive", "profile"]).default("drive"),
  type: z.enum(["image", "video", "audio", "file"]),
  filename: z.string().min(1).max(512),
  originalName: z.string().min(1).max(255),
  mimeType: z.string().min(3).max(128),
  size: z.number().int().positive(),
  metadata: z.record(z.any()).optional(),
});

const fileQuerySchema = z.object({
  filename: z.string().min(1).max(512),
});

module.exports = {
  presignSchema,
  completeSchema,
  fileQuerySchema,
};
