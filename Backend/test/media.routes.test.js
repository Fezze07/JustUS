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
}));

const { adminSupabase, deleteObject, resetRateLimitState } = require("../all_imports");
const { createApp } = require("../app");

describe("media routes", () => {
  beforeEach(() => {
    adminSupabase.from.mockReset();
    deleteObject.mockClear();
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
    // getSignedDownloadUrl looks the row up with .single(), not .maybeSingle().
    const driveItemRow = (overrides = {}) => ({
      id: 5,
      user_id: 42,
      partner_id: 77,
      ...overrides,
    });

    const mockDriveItems = (row) => {
      adminSupabase.from.mockImplementation((table) => {
        if (table === "drive_items") {
          return createQueryBuilder({
            single: jest.fn().mockResolvedValue({ data: row, error: null }),
          });
        }
        return createQueryBuilder();
      });
    };

    test("redirects an owned drive item to its signed R2 download URL", async () => {
      mockDriveItems(driveItemRow());

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/42/memory.jpg" });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        "https://r2.test.local/download/uploads/42/memory.jpg",
      );
    });

    test("denies a download for a caller who is neither owner nor partner", async () => {
      // The auth mock always returns profileId 42, so a row owned by someone
      // else with no partner link must be refused.
      mockDriveItems(driveItemRow({ user_id: 999, partner_id: 888 }));

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/999/secret.jpg" });

      expect(response.status).toBe(403);
      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe("AUTH-FAIL-004");
    });

    test("returns 404 when the filename is not in the drive_items table", async () => {
      mockDriveItems(null);

      const response = await request(createApp())
        .get("/api/v1/media/file")
        .query({ filename: "uploads/42/ghost.jpg" });

      expect(response.status).toBe(404);
      expect(response.body.error.code).toBe("DB-NOT_FOUND-001");
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

  test("stores drive metadata after a successful upload completion", async () => {
    const driveItemsQuery = createQueryBuilder({
      insert: jest.fn(() => driveItemsQuery),
      select: jest.fn(() => driveItemsQuery),
      single: jest.fn().mockResolvedValue({
        data: {
          id: 10,
          filename: "uploads/42/test-memory.jpg",
          partner_id: 77,
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
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.item.id).toBe(10);
  });

  test("deletes a drive item and its R2 object through the delete endpoint", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 10,
          user_id: 42,
          partner_id: 77,
          filename: "uploads/42/test-memory.jpg",
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
    expect(driveItemsQuery.select).toHaveBeenCalledWith(
      "id, user_id, partner_id, filename, metadata"
    );
    expect(driveItemsQuery.delete).toHaveBeenCalledWith();
    expect(driveItemsQuery.eq).toHaveBeenCalledWith("id", 10);
    expect(driveItemsQuery.or).toHaveBeenCalledWith("user_id.eq.42,partner_id.eq.42");
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
          user_id: 42,
          partner_id: 77,
          filename: "uploads/42/main.jpg",
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

  test("still deletes the drive item row when the R2 cleanup fails", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 14,
          user_id: 42,
          partner_id: 77,
          filename: "uploads/42/failing.jpg",
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

  test("deletes the drive item row when the item has no R2 filename", async () => {
    const driveItemsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          id: 12,
          user_id: 42,
          partner_id: 77,
          filename: null,
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
          user_id: 99,
          partner_id: 100,
          filename: "uploads/99/foreign.jpg",
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
      .send({ id: 13 });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-004");
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
