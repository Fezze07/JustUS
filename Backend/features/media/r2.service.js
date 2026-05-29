const path = require("path");
const crypto = require("crypto");
const { S3Client, PutObjectCommand, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { env } = require("../../all_imports");

const allowedMimeTypes = {
  image: ["image/jpeg", "image/png", "image/webp", "image/gif"],
  video: ["video/mp4", "video/quicktime", "video/x-msvideo"],
  audio: ["audio/mpeg", "audio/mp4", "audio/ogg", "audio/wav"],
  file: ["application/pdf", "application/octet-stream"],
};

let r2Client;

function isConfigured() {
  return Boolean(
    env.r2AccessKeyId &&
      env.r2SecretAccessKey &&
      env.r2Endpoint &&
      env.r2BucketName
  );
}

function getClient() {
  if (!isConfigured()) {
    throw new Error("R2 is not configured");
  }

  if (!r2Client) {
    r2Client = new S3Client({
      region: "auto",
      endpoint: env.r2Endpoint,
      credentials: {
        accessKeyId: env.r2AccessKeyId,
        secretAccessKey: env.r2SecretAccessKey,
      },
    });
  }

  return r2Client;
}

function sanitizeFilename(filename) {
  const extension = path.extname(filename).toLowerCase();
  const basename = path
    .basename(filename, extension)
    .replace(/[^a-zA-Z0-9-_]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48) || "file";

  return {
    extension,
    basename,
  };
}

function validateUpload({ type, mimeType, size }) {
  if (size > env.maxUploadBytes) {
    throw new Error(`File too large. Max allowed: ${env.maxUploadBytes} bytes`);
  }

  const allowed = allowedMimeTypes[type] ?? [];
  if (allowed.length > 0 && !allowed.includes(mimeType)) {
    throw new Error(`Unsupported MIME type: ${mimeType}`);
  }
}

function buildObjectKey({ userId, folder, filename }) {
  const safeFolder = (folder || "uploads").replace(/[^a-zA-Z0-9/_-]+/g, "");
  const { extension, basename } = sanitizeFilename(filename);
  const unique = `${Date.now()}-${crypto.randomUUID()}`;
  return `${safeFolder}/${userId}/${unique}-${basename}${extension}`;
}

async function createUploadUrl({ userId, type, filename, mimeType, size, folder }) {
  validateUpload({ type, mimeType, size });
  const key = buildObjectKey({ userId, folder, filename });

  const command = new PutObjectCommand({
    Bucket: env.r2BucketName,
    Key: key,
    ContentType: mimeType,
    ContentLength: size,
  });

  const uploadUrl = await getSignedUrl(getClient(), command, {
    expiresIn: env.mediaUploadUrlExpiresSeconds,
  });

  return {
    uploadUrl,
    key,
    expiresIn: env.mediaUploadUrlExpiresSeconds,
  };
}

async function createDownloadUrl(key) {
  const command = new GetObjectCommand({
    Bucket: env.r2BucketName,
    Key: key,
  });

  return getSignedUrl(getClient(), command, {
    expiresIn: env.mediaDownloadUrlExpiresSeconds,
  });
}

module.exports = {
  isConfigured,
  createUploadUrl,
  createDownloadUrl,
  validateUpload,
};
