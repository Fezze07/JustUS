const { mockS3Send } = (() => {
  const mockSend = jest.fn().mockImplementation(async (command) => {
    if (command._type === "list_multipart") {
      return {
        Uploads: [
          { Key: "uploads/stale_multipart.jpg", UploadId: "upload-1", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
          { Key: "uploads/fresh_multipart.jpg", UploadId: "upload-2", Initiated: new Date(Date.now() - 1 * 3600 * 1000).toISOString() },
        ],
      };
    }
    return {};
  });
  return { mockS3Send: mockSend };
})();

jest.mock("@aws-sdk/client-s3", () => ({
  S3Client: jest.fn(() => ({ send: mockS3Send })),
  ListMultipartUploadsCommand: jest.fn((args) => ({ _type: "list_multipart", ...args })),
  AbortMultipartUploadCommand: jest.fn((args) => ({ _type: "abort_multipart", ...args })),
}));

const mockDeleteObjects = jest.fn().mockResolvedValue(1);
const mockListObjects = jest.fn().mockImplementation(async (prefix) => {
  if (prefix === "uploads/") {
    return [
      { key: "uploads/active_file.jpg", lastModified: Date.now() - 1000 },
      { key: "uploads/stale_orphan.jpg", lastModified: Date.now() - 48 * 3600 * 1000 },
    ];
  }
  return [];
});

jest.mock("../features/media/r2.service", () => ({
  listObjects: mockListObjects,
  deleteObjects: mockDeleteObjects,
  isConfigured: jest.fn().mockReturnValue(true),
}));

jest.mock("../config/db", () => {
  const tablesData = {
    drive_items: [{ filename: "uploads/active_file.jpg", metadata: null }],
    user_profiles: [{ profile_pic_url: "profile/active_pic.jpg" }],
  };

  const queryBuilder = {
    delete: jest.fn().mockReturnThis(),
    select: jest.fn((cols) => queryBuilder),
    not: jest.fn((col, op, val) => {
      queryBuilder._currentNot = { col, op, val };
      return queryBuilder;
    }),
    lt: jest.fn().mockResolvedValue({ error: null, count: 1 }),
  };

  // Allow from() to return mock data for drive_items and user_profiles select queries
  const fromMock = jest.fn((tableName) => {
    if (tableName === "drive_items") {
      return {
        select: jest.fn().mockReturnValue({
          not: jest.fn().mockResolvedValue({ error: null, data: tablesData.drive_items }),
        }),
      };
    }
    if (tableName === "user_profiles") {
      return {
        select: jest.fn().mockReturnValue({
          not: jest.fn().mockResolvedValue({ error: null, data: tablesData.user_profiles }),
        }),
      };
    }
    return queryBuilder;
  });

  return {
    adminSupabase: {
      from: fromMock,
      rpc: jest.fn().mockResolvedValue({ data: 0, error: null }),
    },
    __queryBuilder: queryBuilder,
    __fromMock: fromMock,
  };
});

const { adminSupabase, __queryBuilder, __fromMock } = require("../config/db");
const { startRetentionJobs, stopRetentionJobs } = require("../core/jobs/retentionJob");
const { AbortMultipartUploadCommand } = require("@aws-sdk/client-s3");

describe("retentionJob - all cleanup jobs", () => {
  let now;

  beforeEach(() => {
    jest.clearAllMocks();
    now = Date.now();
  });

  afterEach(() => {
    stopRetentionJobs();
  });

  test("runs all retention jobs on startup", async () => {
    await startRetentionJobs();

    // 1. Nonce sweep test
    expect(adminSupabase.from).toHaveBeenCalledWith("request_nonces");
    expect(__queryBuilder.delete).toHaveBeenCalledWith({ count: "exact" });
    expect(__queryBuilder.lt).toHaveBeenCalledWith("expires_at", expect.any(String));

    // 2. Old logs sweep test (security_events, api_access, api_errors)
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_security_events");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_api_access");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_api_errors");

    // 3. User devices sweep test (dead-session prune + 30-day cutoff)
    expect(adminSupabase.from).toHaveBeenCalledWith("user_devices");
    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "purge_user_devices_dead_sessions"
    );
    const userDeviceLtCalls = __queryBuilder.lt.mock.calls.filter(call => call[0] === "updated_at");
    expect(userDeviceLtCalls.length).toBeGreaterThan(0);
    const userDeviceCutoff = new Date(userDeviceLtCalls[0][1]).getTime();
    const expectedUserDeviceCutoff = now - 30 * 24 * 60 * 60 * 1000;
    expect(Math.abs(userDeviceCutoff - expectedUserDeviceCutoff)).toBeLessThan(5000);

    // 4. R2 stale multipart upload sweep test
    expect(mockS3Send).toHaveBeenCalled();
    const abortCalls = mockS3Send.mock.calls.filter(
      call => call[0]._type === "abort_multipart"
    );
    expect(abortCalls.length).toBe(1);
    expect(AbortMultipartUploadCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        Key: "uploads/stale_multipart.jpg",
        UploadId: "upload-1",
      })
    );

    // 5. R2 orphan object sweep test
    expect(mockListObjects).toHaveBeenCalledWith("uploads/");
    expect(mockListObjects).toHaveBeenCalledWith("profile/");
    expect(mockDeleteObjects).toHaveBeenCalledWith(["uploads/stale_orphan.jpg"]);
  });

  test("ages out unrefreshed rows even when the dead-session prune found none", async () => {
    adminSupabase.rpc.mockResolvedValue({ data: 4, error: null });
    __queryBuilder.lt.mockResolvedValue({ error: null, count: 2 });

    await startRetentionJobs();

    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "purge_user_devices_dead_sessions"
    );
    expect(__queryBuilder.lt).toHaveBeenCalledWith(
      "updated_at",
      expect.any(String)
    );
  });

  test("swallows a dead-session prune failure so the remaining sweeps still run", async () => {
    adminSupabase.rpc.mockResolvedValue({
      data: null,
      error: { message: "rpc rejected" },
    });

    await expect(startRetentionJobs()).resolves.toBeUndefined();
  });
});

