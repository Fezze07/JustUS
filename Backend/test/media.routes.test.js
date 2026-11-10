const request = require("supertest");
const { createQueryBuilder } = require("./support/mockSupabase");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logError: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
  resolveDeviceId: jest.fn().mockResolvedValue(null),
}));

jest.mock("../config/db", () => ({
  adminSupabase: {
    from: jest.fn(),
    rpc: jest.fn(),
  },
  authSupabase: {
    auth: {
      getUser: jest.fn(),
    },
  },
  createUserScopedClient: jest.fn(),
}));

jest.mock("../middleware/authMiddleware", () =>
  jest.fn((req, _res, next) => {
    req.user = {
      id: "auth-user-1",
      profileId: 42,
      publicEmail: "user@example.com",
      capabilities: ["can_media_upload"],
      role: "user",
    };
    next();
  })
);

jest.mock("../middleware/requireSignedRequest", () =>
  jest.fn(() => (_req, _res, next) => next())
);

jest.mock("../features/media/r2.service", () => ({
  isConfigured: jest.fn(() => true),
  createUploadUrl: jest.fn(async ({ userId, filename }) => ({
    uploadUrl: `https://r2.test.local/upload/${userId}/${filename}`,
    key: `uploads/${userId}/test-${filename}`,
    expiresIn: 300,
  })),
  createDownloadUrl: jest.fn(async (filename) => `https://r2.test.local/download/${filename}`),
  deleteObject: jest.fn(async () => undefined),
  deleteObjectsByPrefix: jest.fn(async () => 0),
}));

jest.mock("../utils/misc/partnershipUtils", () => ({
  getPartnerId: jest.fn(async () => 77),
  getPartnershipId: jest.fn(async () => 5),
  isPartnershipMember: jest.fn(async () => true),
}));

const { adminSupabase, deleteObject, resetRateLimitState } = require("../all_imports");
const {
  getPartnerId,
  getPartnershipId,
  isPartnershipMember,
} = require("../utils/misc/partnershipUtils");
const { createApp } = require("../app");

describe("media routes", () => {
  beforeEach(() => {
    adminSupabase.from.mockReset();
    deleteObject.mockClear();
    getPartnerId.mockReset();
    getPartnerId.mockResolvedValue(77);
    getPartnershipId.mockClear();
    isPartnershipMember.mockReset();
    isPartnershipMember.mockResolvedValue(true);
    // mediaRateLimit is createIpUserRateLimit({ ipMax: 60, userMax: 40 }) and its
    // buckets are module-level, so without this reset each test starts where the
    // previous one stopped and a later assertion fails with an unrelated 429.
    resetRateLimitState();
  });

  // GET /api/v1/media/file is the endpoint the Flutter client uses to view
  // media (ApiService -> ApiRoutes.mediaFile). It had no coverage at all, so a
  // regression in the redirect-to-signed-download path would only have been
  // caught in production.
  describe("GET /file (signed download redirect)", () => {
    const driveItemRow = (overrides = {}) => ({
      id: 5,
      partnership_id: 5,
      ...overrides,
    });

    const mockMediaTables = ({
      driveByName = null,
      driveByThumbnail = null,
      profileOwner = null,
    } = {}) => {
      const driveNameQuery = createQueryBuilder({
        maybeSingle: jest.fn().mockResolvedValue({ data: driveByName, error: null }),
      });
      const driveThumbnailQuery = createQueryBuilder({
        maybeSingle: jest.fn().mockResolvedValue({ data: driveByThumbnail, error: null }),
      });
      const profileQuery = createQueryBuilder({
        maybeSingle: jest.fn().mockResolvedValue({
          data: profileOwner == null ? null : { user_id: profileOwner },
          error: null,
        }),
      });
      let driveCalls = 0;

      adminSupabase.from.mockImplementation((table) => {
        if (table === "drive_items") {
          driveCalls += 1;
          return driveCalls === 1 ? driveNameQuery : driveThumbnailQuery;
        }
        if (table === "user_profiles") return profileQuery;
        return createQueryBuilder();
      });

      return { driveNameQuery, driveThumbnailQuery, profileQuery };
    };

    test("redirects a partnered drive item to its signed R2 download URL", async () => {
      const { driveNameQuery } = mockMediaTables({ driveByName: driveItemRow() });

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/42/memory.jpg" });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        "https://r2.test.local/download/uploads/42/memory.jpg",
      );
      expect(driveNameQuery.select).toHaveBeenCalledWith("partnership_id");
      expect(driveNameQuery.eq).toHaveBeenCalledWith("name", "uploads/42/memory.jpg");
      expect(isPartnershipMember).toHaveBeenCalledWith(5, 42);
    });

    test("redirects a generated thumbnail found in metadata.thumbnail", async () => {
      const { driveNameQuery, driveThumbnailQuery } = mockMediaTables({
        driveByThumbnail: driveItemRow(),
      });

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/42/memory_thumb.jpg" });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        "https://r2.test.local/download/uploads/42/memory_thumb.jpg",
      );
      expect(driveNameQuery.eq).toHaveBeenCalledWith("name", "uploads/42/memory_thumb.jpg");
      expect(driveThumbnailQuery.eq).toHaveBeenCalledWith(
        "metadata->>thumbnail",
        "uploads/42/memory_thumb.jpg",
      );
    });

    test("redirects an owner's profile picture", async () => {
      mockMediaTables({ profileOwner: 42 });

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "profile/42/avatar.jpg" });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        "https://r2.test.local/download/profile/42/avatar.jpg",
      );
    });

    test("redirects an accepted partner's profile picture", async () => {
      mockMediaTables({ profileOwner: 77 });

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "profile/77/avatar.jpg" });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        "https://r2.test.local/download/profile/77/avatar.jpg",
      );
      expect(getPartnerId).toHaveBeenCalledWith(42);
    });

    test("denies a profile picture belonging to an unrelated user", async () => {
      mockMediaTables({ profileOwner: 99 });

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "profile/99/avatar.jpg" });

      expect(response.status).toBe(403);
      expect(response.body.error.code).toBe("AUTH-FAIL-004");
    });

    test("denies a download for a caller outside the item partnership", async () => {
      // The auth mock always returns profileId 42; the row's partnership has
      // other members, so the membership check must refuse it.
      mockMediaTables({ driveByName: driveItemRow({ partnership_id: 6 }) });
      isPartnershipMember.mockResolvedValueOnce(false);

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/999/secret.jpg" });

      expect(response.status).toBe(403);
      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe("AUTH-FAIL-004");
    });

    test("rejects a drive row that points at another user's key", async () => {
      mockMediaTables({ driveByName: driveItemRow() });
      isPartnershipMember
        .mockResolvedValueOnce(true)
        .mockResolvedValueOnce(false);

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/99/foreign.jpg" });

      expect(response.status).toBe(403);
      expect(response.body.error.code).toBe("AUTH-FAIL-004");
      expect(isPartnershipMember).toHaveBeenCalledWith(5, 99);
    });

    test("rejects a key outside the allowed storage roots", async () => {
      mockMediaTables();

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "custom/42/file.jpg" });

      expect(response.status).toBe(403);
      expect(response.body.error.code).toBe("AUTH-FAIL-004");
    });

    test("returns 404 when the filename is in neither drive_items nor user_profiles", async () => {
      const { driveNameQuery, driveThumbnailQuery, profileQuery } = mockMediaTables();

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/42/ghost.jpg" });

      expect(response.status).toBe(404);
      expect(response.body.error.code).toBe("DB-NOT_FOUND-001");
      expect(driveNameQuery.eq).toHaveBeenCalledWith("name", "uploads/42/ghost.jpg");
      expect(driveThumbnailQuery.eq).toHaveBeenCalledWith(
        "metadata->>thumbnail",
        "uploads/42/ghost.jpg",
      );
      expect(profileQuery.eq).toHaveBeenCalledWith(
        "profile_pic_url",
        "uploads/42/ghost.jpg",
      );
    });

    test("rejects a download request with no filename", async () => {
      const response = await request(createApp()).get("/api/v1/media/file");

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe("API-VALIDATION-001");
    });
  });

  test("returns a signed upload URL", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/upload-url")
      .send({
        type: "image",
        filename: "memory.jpg",
        mimeType: "image/jpeg",
        size: 4096,
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.uploadUrl).toContain("https://r2.test.local/upload/42/memory.jpg");
    expect(response.body.filename).toContain("uploads/42/");
  });

  test("rejects an upload folder outside uploads/profile", async () => {
    const response = await request(createApp())
      .post("/api/v1/media/upload-url")
      .send({
        type: "image",
        filename: "memory.jpg",
        mimeType: "image/jpeg",
        size: 4096,
        folder: "custom",
      });

    expect(response.status).toBe(400);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("accepts the profile upload folder", async () => {
    const response = await request(createApp())
      .post("/api/v1/media/upload-url")
      .send({
        type: "image",
        filename: "avatar.jpg",
        mimeType: "image/jpeg",
        size: 4096,
        folder: "profile",
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
  });

  test("rejects upload URL generation with invalid payload", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/upload-url")
      .send({
        type: "invalid_type", // Must be image, video, audio, or file
        filename: "", // Must be at least 1 char
        size: -100, // Must be positive
      });

    expect(response.status).toBe(400);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("rejects upload completion when the storage key does not belong to the user", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/complete")
      .send({
        kind: "drive",
        type: "image",
        filename: "uploads/999/foreign-file.jpg",
        originalName: "foreign-file.jpg",
        mimeType: "image/jpeg",
        size: 2048,
      });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-004");
  });

  test("rejects upload completion when the thumbnail key does not belong to the user", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/complete")
      .send({
        kind: "drive",
        type: "image",
        filename: "uploads/42/test-memory.jpg",
        originalName: "memory.jpg",
        mimeType: "image/jpeg",
        size: 2048,
        metadata: { thumbnail: "uploads/999/foreign-thumb.jpg" },
      });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-004");
    expect(adminSupabase.from).not.toHaveBeenCalled();
  });

  test("upserts drive metadata after a successful upload completion", async () => {
    const driveItemsQuery = createQueryBuilder({
      upsert: jest.fn(() => driveItemsQuery),
      select: jest.fn(() => driveItemsQuery),
      single: jest.fn().mockResolvedValue({
        data: {
          id: 10,
          name: "uploads/42/test-memory.jpg",
          partnership_id: 5,
        },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/complete")
      .send({
        kind: "drive",
        type: "image",
        filename: "uploads/42/test-memory.jpg",
        originalName: "memory.jpg",
        mimeType: "image/jpeg",
        size: 4096,
        metadata: { thumbnail: "uploads/42/test-thumb.jpg" },
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.item.id).toBe(10);
    expect(getPartnershipId).toHaveBeenCalledWith(42);
    expect(driveItemsQuery.upsert).toHaveBeenCalledWith(
      {
        partnership_id: 5,
        type: "image",
        name: "uploads/42/test-memory.jpg",
        original_name: "memory.jpg",
        mime_type: "image/jpeg",
        size: 4096,
        metadata: {
          thumbnail: "uploads/42/test-thumb.jpg",
          source: "backend-signed-url",
        },
      },
      { onConflict: "name" }
    );
  });

  test("a retried completion upserts on name instead of inserting a duplicate", async () => {
    const driveItemsQuery = createQueryBuilder({
      upsert: jest.fn(() => driveItemsQuery),
      select: jest.fn(() => driveItemsQuery),
      single: jest.fn().mockResolvedValue({
        data: { id: 10, name: "uploads/42/test-memory.jpg" },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation(() => driveItemsQuery);

    const app = createApp();
    const payload = {
      kind: "drive",
      type: "image",
      filename: "uploads/42/test-memory.jpg",
      originalName: "memory.jpg",
      mimeType: "image/jpeg",
      size: 4096,
    };

    const first = await request(app).post("/api/v1/media/complete").send(payload);
    const retry = await request(app).post("/api/v1/media/complete").send(payload);

    expect(first.status).toBe(200);
    expect(retry.status).toBe(200);
    expect(driveItemsQuery.upsert).toHaveBeenCalledTimes(2);
    expect(driveItemsQuery.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({ name: "uploads/42/test-memory.jpg" }),
      { onConflict: "name" }
    );
  });

  test("deletes a drive item and its R2 object through the delete endpoint", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 10,
          partnership_id: 5,
          name: "uploads/42/test-memory.jpg",
        },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 10 });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(isPartnershipMember).toHaveBeenCalledWith(5, 42);
    expect(driveItemsQuery.select).toHaveBeenCalledWith(
      "id, partnership_id, name, metadata"
    );
    expect(driveItemsQuery.delete).toHaveBeenCalledWith();
    expect(driveItemsQuery.eq).toHaveBeenCalledWith("id", 10);
    expect(driveItemsQuery.eq).toHaveBeenCalledWith("partnership_id", 5);
    expect(deleteObject).toHaveBeenCalledWith("uploads/42/test-memory.jpg");

    const deleteCallIndex = driveItemsQuery.delete.mock.invocationCallOrder[0];
    const r2CallIndex = deleteObject.mock.invocationCallOrder[0];
    expect(deleteCallIndex).toBeLessThan(r2CallIndex);
  });

  test("deletes the full-size object and its thumbnail on delete", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 15,
          partnership_id: 5,
          name: "uploads/42/main.jpg",
          metadata: { thumbnail: "uploads/42/thumb.jpg" },
        },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 15 });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(deleteObject).toHaveBeenCalledWith("uploads/42/main.jpg");
    expect(deleteObject).toHaveBeenCalledWith("uploads/42/thumb.jpg");
  });

  test("does not delete a thumbnail outside the main object's owner prefix", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 16,
          partnership_id: 5,
          name: "uploads/42/main.jpg",
          metadata: { thumbnail: "uploads/999/foreign-thumb.jpg" },
        },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const response = await request(createApp())
      .post("/api/v1/media/delete")
      .send({ id: 16 });

    expect(response.status).toBe(200);
    expect(deleteObject).toHaveBeenCalledTimes(1);
    expect(deleteObject).toHaveBeenCalledWith("uploads/42/main.jpg");
  });

  test("still deletes the drive item row when the R2 cleanup fails", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 14,
          partnership_id: 5,
          name: "uploads/42/failing.jpg",
        },
        error: null,
      }),
    });

    deleteObject.mockRejectedValueOnce(new Error("R2 unavailable"));

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 14 });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(driveItemsQuery.delete).toHaveBeenCalled();
  });

  test("deletes the drive item row when the item has no R2 storage key", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 12,
          partnership_id: 5,
          name: null,
        },
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 12 });

    expect(response.status).toBe(200);
    expect(deleteObject).not.toHaveBeenCalled();
  });

  test("rejects deletion of a drive item outside the caller partnership", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 13,
          partnership_id: 6,
          name: "uploads/99/foreign.jpg",
        },
        error: null,
      }),
    });

    isPartnershipMember.mockResolvedValueOnce(false);

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 13 });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-004");
    expect(isPartnershipMember).toHaveBeenCalledWith(6, 42);
    expect(driveItemsQuery.delete).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });

  test("treats a delete of a non-existing drive item as success (idempotent)", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: null,
        error: null,
      }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "drive_items") {
        return driveItemsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: 404 });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(driveItemsQuery.delete).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });

  test("rejects deletion with an invalid payload", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/media/delete")
      .send({ id: "not-a-number" });

    expect(response.status).toBe(400);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });
});
