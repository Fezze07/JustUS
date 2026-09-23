const path = require("path");
const crypto = require("crypto");
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectCommand,
  DeleteObjectsCommand,
} = require("@aws-sdk/client-s3");
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

async function listObjectKeys(prefix) {
  const objects = await listObjects(prefix);
  return objects.map((object) => object.key);
}

async function listObjects(prefix) {
  if (!prefix) return [];
  const objects = [];
  let continuationToken;

  do {
    const command = new ListObjectsV2Command({
      Bucket: env.r2BucketName,
      Prefix: prefix,
      ContinuationToken: continuationToken,
    });

    const result = await getClient().send(command);

    if (result.Contents) {
      for (const obj of result.Contents) {
        if (obj.Key) {
          objects.push({
            key: obj.Key,
            lastModified: obj.LastModified ? new Date(obj.LastModified).getTime() : null,
          });
        }
      }
    }

    continuationToken = result.IsTruncated
      ? result.NextContinuationToken
      : undefined;
  } while (continuationToken);

  return objects;
}

async function deleteObject(key) {
  if (!isConfigured() || !key) return;

  await getClient().send(
    new DeleteObjectCommand({
      Bucket: env.r2BucketName,
      Key: key,
    })
  );
}

async function deleteObjects(keys) {
  if (!isConfigured() || keys.length === 0) return 0;

  let deleted = 0;
  for (let index = 0; index < keys.length; index += 1000) {
    const batch = keys.slice(index, index + 1000);
    const result = await getClient().send(
      new DeleteObjectsCommand({
        Bucket: env.r2BucketName,
        Delete: {
          Objects: batch.map((Key) => ({ Key })),
          Quiet: true,
        },
      })
    );

    deleted += batch.length - (result.Errors?.length ?? 0);

    if (result.Errors?.length) {
      throw new Error(
        `Failed to delete R2 objects: ${JSON.stringify(result.Errors)}`
      );
    }
  }

  return deleted;
}

async function deleteObjectsByPrefix(prefix) {
  if (!isConfigured() || !prefix) return 0;

  const keys = await listObjectKeys(prefix);

  return deleteObjects(keys);
}

module.exports = {
  isConfigured,
  createUploadUrl,
  createDownloadUrl,
  listObjectKeys,
  listObjects,
  deleteObject,
  deleteObjects,
  deleteObjectsByPrefix,
  validateUpload,
};
