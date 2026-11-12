const defaultMultipartSend = async (command) => {
  if (command._type === "list_multipart") {
    return {
      IsTruncated: false,
      Uploads: [
        { Key: "uploads/stale_multipart.jpg", UploadId: "upload-1", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
        { Key: "uploads/fresh_multipart.jpg", UploadId: "upload-2", Initiated: new Date(Date.now() - 1 * 3600 * 1000).toISOString() },
      ],
    };
  }
  return {};
};
const mockS3Send = jest.fn(defaultMultipartSend);

jest.mock("@aws-sdk/client-s3", () => ({
  S3Client: jest.fn(() => ({ send: mockS3Send })),
  ListMultipartUploadsCommand: jest.fn((args) => ({ _type: "list_multipart", ...args })),
  AbortMultipartUploadCommand: jest.fn((args) => ({ _type: "abort_multipart", ...args })),
}));

const mockDeleteObjects = jest.fn().mockResolvedValue(1);
const mockDefaultListObjects = async (prefix) => {
  if (prefix === "uploads/") {
    return [
      { key: "uploads/active_file.jpg", lastModified: Date.now() - 1000 },
      { key: "uploads/stale_orphan.jpg", lastModified: Date.now() - 48 * 3600 * 1000 },
    ];
  }
  return [];
};
const mockListObjects = jest.fn(mockDefaultListObjects);

jest.mock("../features/media/r2.service", () => ({
  listObjects: mockListObjects,
  deleteObjects: mockDeleteObjects,
  isConfigured: jest.fn().mockReturnValue(true),
}));

jest.mock("../core/logger", () => ({
  logError: jest.fn().mockResolvedValue(undefined),
  logInfo: jest.fn(),
}));

jest.mock("../config/db", () => {
  const initialRows = () => ({
    drive_items: [{ name: "uploads/active_file.jpg", metadata: null }],
    user_profiles: [{ profile_pic_url: "profile/active_pic.jpg" }],
  });

  const tableState = {
    drive_items: { rows: initialRows().drive_items, error: null, errorByFrom: {} },
    user_profiles: { rows: initialRows().user_profiles, error: null, errorByFrom: {} },
  };
  const rangeCalls = [];
  const selectCalls = [];

  const createSelectQuery = (tableName) => {
    const query = {
      not: jest.fn(() => query),
      order: jest.fn((column) => {
        query._orderColumn = column;
        return query;
      }),
      range: jest.fn(async (from, to) => {
        rangeCalls.push({ table: tableName, from, to, order: query._orderColumn });
        const state = tableState[tableName];
        const error = state.errorByFrom[from] ?? state.error;
        if (error) return { data: null, error };
        return { data: state.rows.slice(from, to + 1), error: null };
      }),
    };
    query.select = jest.fn((columns) => {
      selectCalls.push({ table: tableName, columns });
      return query;
    });
    return query;
  };

  const queryBuilder = {
    delete: jest.fn().mockReturnThis(),
    select: jest.fn(() => queryBuilder),
    not: jest.fn(() => queryBuilder),
    lt: jest.fn().mockResolvedValue({ error: null, count: 1 }),
  };

  const fromMock = jest.fn((tableName) =>
    tableState[tableName] ? createSelectQuery(tableName) : queryBuilder
  );

  return {
    adminSupabase: {
      from: fromMock,
      rpc: jest.fn().mockResolvedValue({ data: 0, error: null }),
    },
    __queryBuilder: queryBuilder,
    __tableState: tableState,
    __rangeCalls: rangeCalls,
    __selectCalls: selectCalls,
    __resetTables: () => {
      const rows = initialRows();
      tableState.drive_items = { rows: rows.drive_items, error: null, errorByFrom: {} };
      tableState.user_profiles = { rows: rows.user_profiles, error: null, errorByFrom: {} };
      rangeCalls.length = 0;
      selectCalls.length = 0;
    },
  };
});

const {
  adminSupabase,
  __queryBuilder,
  __tableState,
  __rangeCalls,
  __selectCalls,
  __resetTables,
} = require("../config/db");
const { startRetentionJobs, stopRetentionJobs, fetchReferencedKeys } = require("../core/jobs/retentionJob");
const { logError, logInfo } = require("../core/logger");
const { AbortMultipartUploadCommand } = require("@aws-sdk/client-s3");

describe("retentionJob - all cleanup jobs", () => {
  let now;

  beforeEach(() => {
    jest.clearAllMocks();
    mockS3Send.mockImplementation(defaultMultipartSend);
    mockListObjects.mockImplementation(mockDefaultListObjects);
    __resetTables();
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

    // 2. Old logs sweep test (security_events, api_access, api_errors,
    //    auth_failures, notifications)
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_security_events");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_api_access");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_api_errors");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_auth_failures");
    expect(adminSupabase.from).toHaveBeenCalledWith("logs_notifications");
    const logCutoffCalls = __queryBuilder.lt.mock.calls.filter(
      (call) => call[0] === "created_at"
    );
    expect(logCutoffCalls).toHaveLength(5);

    // 3. User devices sweep test (dead-session prune + 30-day cutoff)
    expect(adminSupabase.from).toHaveBeenCalledWith("user_devices");
    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "device_purge_dead_sessions"
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
    expect(__selectCalls).toContainEqual({
      table: "drive_items",
      columns: "name, metadata",
    });
    expect(__selectCalls).toContainEqual({
      table: "user_profiles",
      columns: "profile_pic_url",
    });
    expect(mockListObjects).toHaveBeenCalledWith("uploads/");
    expect(mockListObjects).toHaveBeenCalledWith("profile/");
    expect(mockDeleteObjects).toHaveBeenCalledWith(["uploads/stale_orphan.jpg"]);
  });

  test("paginates multipart listings and aborts stale uploads on every page", async () => {
    const listCalls = [];
    mockS3Send.mockImplementation(async (command) => {
      if (command._type !== "list_multipart") return {};
      listCalls.push(command);
      if (!command.KeyMarker) {
        return {
          IsTruncated: true,
          NextKeyMarker: "uploads/page2-key",
          NextUploadIdMarker: "upload-page2",
          Uploads: [
            { Key: "uploads/page1_stale.jpg", UploadId: "upload-p1", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
          ],
        };
      }
      return {
        IsTruncated: false,
        Uploads: [
          { Key: "uploads/page2_stale.jpg", UploadId: "upload-p2", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
        ],
      };
    });

    await startRetentionJobs();

    expect(listCalls).toHaveLength(2);
    expect(listCalls[1]).toEqual(
      expect.objectContaining({
        KeyMarker: "uploads/page2-key",
        UploadIdMarker: "upload-page2",
      })
    );
    const abortedKeys = mockS3Send.mock.calls
      .filter((call) => call[0]._type === "abort_multipart")
      .map((call) => call[0].Key);
    expect(abortedKeys).toEqual([
      "uploads/page1_stale.jpg",
      "uploads/page2_stale.jpg",
    ]);
  });

  test("attempts later aborts when one multipart abort fails", async () => {
    mockS3Send.mockImplementation(async (command) => {
      if (command._type === "list_multipart") {
        return {
          IsTruncated: false,
          Uploads: [
            { Key: "uploads/fail_abort.jpg", UploadId: "upload-fail", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
            { Key: "uploads/after_fail.jpg", UploadId: "upload-after", Initiated: new Date(Date.now() - 72 * 3600 * 1000).toISOString() },
          ],
        };
      }
      if (
        command._type === "abort_multipart" &&
        command.Key === "uploads/fail_abort.jpg"
      ) {
        throw new Error("abort rejected");
      }
      return {};
    });

    await expect(startRetentionJobs()).resolves.toBeUndefined();

    const abortedKeys = mockS3Send.mock.calls
      .filter((call) => call[0]._type === "abort_multipart")
      .map((call) => call[0].Key);
    expect(abortedKeys).toEqual([
      "uploads/fail_abort.jpg",
      "uploads/after_fail.jpg",
    ]);
    expect(logError).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "retention.r2_multipart.abort_failed",
        key: "uploads/fail_abort.jpg",
      })
    );
    expect(logInfo).toHaveBeenCalledWith("retention.r2_multipart", {
      aborted: 1,
      failed: 1,
    });
  });

  test("fetchReferencedKeys includes a seeded drive item key", async () => {
    const keys = await fetchReferencedKeys();

    expect(keys.has("uploads/active_file.jpg")).toBe(true);
  });

  test("logs a failed referenced-key source and still runs the multipart sweep", async () => {
    __tableState.drive_items.error = {
      message: "column drive_items.name does not exist",
      code: "42703",
    };

    await startRetentionJobs();

    expect(logError).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "retention.r2_orphan.failed",
        source: "drive_items",
      })
    );
    expect(mockS3Send).toHaveBeenCalled();
    expect(mockDeleteObjects).not.toHaveBeenCalled();
  });

  test("paginates drive_items and keeps an object referenced on the second page", async () => {
    const rows = Array.from({ length: 1001 }, (_, i) => ({
      name: `uploads/u/filler-${i}.jpg`,
      metadata: null,
    }));
    rows[1000] = { name: "uploads/u/keep.jpg", metadata: null };
    __tableState.drive_items.rows = rows;
    mockListObjects.mockImplementation(async (prefix) =>
      prefix === "uploads/"
        ? [
            { key: "uploads/u/keep.jpg", lastModified: now - 48 * 3600 * 1000 },
            { key: "uploads/u/orphan.jpg", lastModified: now - 48 * 3600 * 1000 },
          ]
        : []
    );

    await startRetentionJobs();

    expect(__rangeCalls.filter((call) => call.table === "drive_items")).toEqual([
      { table: "drive_items", from: 0, to: 999, order: "id" },
      { table: "drive_items", from: 1000, to: 1999, order: "id" },
    ]);
    expect(mockDeleteObjects).toHaveBeenCalledWith(["uploads/u/orphan.jpg"]);
  });

  test("paginates user_profiles and keeps a picture referenced on the second page", async () => {
    const rows = Array.from({ length: 1001 }, (_, i) => ({
      profile_pic_url: `profile/pic-${i}.jpg`,
    }));
    rows[1000] = { profile_pic_url: "profile/keep_pic.jpg" };
    __tableState.user_profiles.rows = rows;
    mockListObjects.mockImplementation(async (prefix) =>
      prefix === "profile/"
        ? [
            { key: "profile/keep_pic.jpg", lastModified: now - 48 * 3600 * 1000 },
            { key: "profile/orphan_pic.jpg", lastModified: now - 48 * 3600 * 1000 },
          ]
        : []
    );

    await startRetentionJobs();

    expect(__rangeCalls.filter((call) => call.table === "user_profiles")).toEqual([
      { table: "user_profiles", from: 0, to: 999, order: "user_id" },
      { table: "user_profiles", from: 1000, to: 1999, order: "user_id" },
    ]);
    expect(mockDeleteObjects).toHaveBeenCalledWith(["profile/orphan_pic.jpg"]);
  });

  test("aborts the sweep when a later reference page fails", async () => {
    __tableState.drive_items.rows = Array.from({ length: 1000 }, (_, i) => ({
      name: `uploads/u/filler-${i}.jpg`,
      metadata: null,
    }));
    __tableState.drive_items.errorByFrom[1000] = {
      message: "connection reset",
      code: "08006",
    };

    await startRetentionJobs();

    expect(logError).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "retention.r2_orphan.failed",
        source: "drive_items",
      })
    );
    expect(mockDeleteObjects).not.toHaveBeenCalled();
  });

  test("ages out unrefreshed rows even when the dead-session prune found none", async () => {
    adminSupabase.rpc.mockResolvedValue({ data: 4, error: null });
    __queryBuilder.lt.mockResolvedValue({ error: null, count: 2 });

    await startRetentionJobs();

    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "device_purge_dead_sessions"
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

