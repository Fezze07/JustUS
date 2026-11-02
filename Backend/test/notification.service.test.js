// In-memory stand-in for the `user_devices` table so the delete predicate can be
// exercised as behaviour (a filtered delete), not as a mocked call chain.
const mockDb = { rows: [] };

const mockQueryBuilder = (table) => {
  const filters = { eq: [], in: [] };
  let deleting = false;
  const builder = {
    delete: () => {
      deleting = true;
      return builder;
    },
    select: () => builder,
    not: () => builder,
    eq: (column, value) => {
      filters.eq.push([column, value]);
      return builder;
    },
    in: (column, values) => {
      filters.in.push([column, values]);
      return builder;
    },
    then: (resolve) => {
      if (table !== "user_devices") return resolve({ data: null, error: null });
      const matches = (row) =>
        filters.eq.every(([column, value]) => row[column] === value) &&
        filters.in.every(([column, values]) => values.includes(row[column]));
      if (!deleting) {
        return resolve({ data: mockDb.rows.filter(matches), error: null });
      }
      const deleted = mockDb.rows.filter(matches);
      mockDb.rows = mockDb.rows.filter((row) => !matches(row));
      resolve({ data: deleted, error: null });
    },
  };
  return builder;
};

const mockSendMulticast = jest.fn();
const mockGetPartnerId = jest.fn();
const mockGetCancellationPartnerId = jest.fn();
const mockLogNotification = jest.fn();

jest.mock("../all_imports", () => ({
  adminSupabase: { from: (table) => mockQueryBuilder(table) },
  sendMulticastNotification: (...args) => mockSendMulticast(...args),
  assertDbSuccess: (result) => {
    if (result?.error) throw new Error(result.error.message ?? "db error");
    return result?.data ?? null;
  },
  getPartnerId: (...args) => mockGetPartnerId(...args),
  getCancellationPartnerId: (...args) => mockGetCancellationPartnerId(...args),
  logNotification: (...args) => mockLogNotification(...args),
  AppError: jest.requireActual("../core/errors/AppError").AppError,
}));

const {
  deleteInvalidInstallations,
  dispatchNotification,
  resolveNotificationTarget,
  sendNotificationToUser,
} = require("../features/notifications/notification.service");
const {
  deliverToBatches,
} = require("../features/notifications/notification.utils");

beforeEach(() => {
  mockDb.rows = [];
  mockSendMulticast.mockReset();
  mockGetPartnerId.mockReset();
  mockGetCancellationPartnerId.mockReset();
  mockLogNotification.mockReset();
});

describe("deleteInvalidInstallations user scoping", () => {
  test("leaves an installation reassigned to another user untouched", async () => {
    const row = { id: 1, user_id: 2, installation_id: "fid-shared" };
    mockDb.rows = [{ ...row }];

    const removed = await deleteInvalidInstallations(1, ["fid-shared"]);

    expect(removed).toBe(1);
    expect(mockDb.rows).toEqual([row]);
  });

  test("deletes the row when the installation still belongs to the caller", async () => {
    mockDb.rows = [
      { id: 1, user_id: 1, installation_id: "fid-mine" },
      { id: 2, user_id: 2, installation_id: "fid-other" },
    ];

    await deleteInvalidInstallations(1, ["fid-mine"]);

    expect(mockDb.rows).toEqual([{ id: 2, user_id: 2, installation_id: "fid-other" }]);
  });

  test("returns 0 without querying when every installation id is falsy", async () => {
    expect(await deleteInvalidInstallations(1, [])).toBe(0);
    expect(await deleteInvalidInstallations(1, [null, undefined, ""])).toBe(0);
  });
});

describe("resolveNotificationTarget receiver authorization", () => {
  test("rejects a partnerless sender instead of trusting the body receiverId", async () => {
    mockGetPartnerId.mockResolvedValueOnce(null);

    await expect(
      dispatchNotification({
        type: "missyou",
        senderId: 1,
        payload: { notificationKey: "missyou", receiverId: 77 },
      }),
    ).rejects.toMatchObject({ code: "AUTH-FAIL-004", status: 403 });
    expect(mockLogNotification).not.toHaveBeenCalled();
  });

  test("resolves the receiver from the partnership, not from the body", async () => {
    mockGetPartnerId.mockResolvedValue(42);

    await expect(
      resolveNotificationTarget(
        "missyou",
        { notificationKey: "missyou", receiverId: 42 },
        1,
      ),
    ).resolves.toMatchObject({ receiverId: 42 });

    await expect(
      resolveNotificationTarget(
        "missyou",
        { notificationKey: "missyou", receiverId: 77 },
        1,
      ),
    ).rejects.toMatchObject({ code: "AUTH-FAIL-004" });
  });
});

describe("sendNotificationToUser targets installation ids", () => {
  test("sends fids and deletes a row FCM reports as not registered", async () => {
    mockDb.rows = [
      {
        id: 1,
        user_id: 1,
        installation_id: "fid-dead-0001",
        device_type: "android",
        locale: "en",
      },
    ];
    mockSendMulticast.mockResolvedValueOnce({
      configured: true,
      successCount: 0,
      failureCount: 1,
      responses: [
        {
          success: false,
          error: {
            code: "messaging/installation-id-not-registered",
            message: "not registered",
          },
        },
      ],
    });

    const result = await sendNotificationToUser({
      userId: 1,
      type: "partner",
      title: "Hi",
      body: "There",
    });

    // The send must address Firebase Installation IDs, not registration tokens.
    expect(mockSendMulticast).toHaveBeenCalledWith(
      expect.objectContaining({ fids: ["fid-dead-0001"] })
    );
    expect(result.invalidInstallationsRemoved).toBe(1);
    expect(mockDb.rows).toEqual([]);
  });

  test("keeps the row when the per-message failure is not a dead FID", async () => {
    mockDb.rows = [
      {
        id: 1,
        user_id: 1,
        installation_id: "fid-live-0001",
        device_type: "android",
        locale: "en",
      },
    ];
    mockSendMulticast.mockResolvedValueOnce({
      configured: true,
      successCount: 0,
      failureCount: 1,
      responses: [
        {
          success: false,
          error: { code: "messaging/internal-error", message: "boom" },
        },
      ],
    });

    const result = await sendNotificationToUser({
      userId: 1,
      type: "partner",
      title: "Hi",
      body: "There",
    });

    expect(result.invalidInstallationsRemoved).toBe(0);
    expect(mockDb.rows).toHaveLength(1);
  });

  test("retries a transient FCM failure before giving up", async () => {
    mockDb.rows = [
      {
        id: 1,
        user_id: 1,
        installation_id: "fid-retry-0001",
        device_type: "android",
        locale: "en",
      },
    ];
    mockSendMulticast
      .mockRejectedValueOnce(new Error("transient boom"))
      .mockResolvedValueOnce({
        configured: true,
        successCount: 1,
        failureCount: 0,
        responses: [{ success: true }],
      });

    const result = await sendNotificationToUser({
      userId: 1,
      type: "partner",
      title: "Hi",
    });

    expect(mockSendMulticast).toHaveBeenCalledTimes(2);
    expect(result.delivered).toBe(1);
    expect(result.success).toBe(true);
  });

  test("stops sending further batches once FCM reports it is not configured", async () => {
    mockDb.rows = [
      {
        id: 1,
        user_id: 1,
        installation_id: "fid-en-0001",
        device_type: "android",
        locale: "en",
      },
      {
        id: 2,
        user_id: 1,
        installation_id: "fid-it-0001",
        device_type: "android",
        locale: "it",
      },
    ];
    mockSendMulticast.mockResolvedValueOnce({ configured: false });

    const result = await sendNotificationToUser({
      userId: 1,
      type: "partner",
      title: "Hi",
    });

    expect(mockSendMulticast).toHaveBeenCalledTimes(1);
    expect(result.configured).toBe(false);
    expect(result.delivered).toBe(0);
  });
});

describe("notification locale fallback", () => {
  test("unknown or missing device locales fall back to English", async () => {
    mockSendMulticast.mockResolvedValue({
      configured: true,
      successCount: 1,
      failureCount: 0,
      responses: [{ success: true }],
    });

    await deliverToBatches({
      userId: 1,
      type: "partner",
      title: "Hi",
      data: { notificationKey: "missyou", params: { partnerName: "Alex" } },
      devices: [
        {
          installation_id: "fid-null-0001",
          device_type: "android",
          locale: null,
        },
        {
          installation_id: "fid-fr-0001",
          device_type: "android",
          locale: "fr",
        },
      ],
    });

    const messages = mockSendMulticast.mock.calls.map(([message]) => message);
    expect(messages).toHaveLength(2);
    for (const message of messages) {
      expect(message.notification.title).toBe("Miss You");
      expect(message.notification.body).toBe("Alex misses you");
    }
  });
});

describe("buildFcmMessage APNS payload", () => {
  test("sends no badge so the iOS icon cannot stick at a stale count", async () => {
    mockSendMulticast.mockResolvedValueOnce({
      configured: true,
      successCount: 1,
      failureCount: 0,
      responses: [{ success: true }],
    });

    await deliverToBatches({
      userId: 1,
      type: "partner",
      title: "Hi",
      data: { notificationKey: "missyou" },
      devices: [
        {
          installation_id: "fid-ios-0001",
          device_type: "ios",
          locale: "en",
        },
      ],
    });

    const message = mockSendMulticast.mock.calls[0][0];
    expect(message.apns.payload.aps.alert).toBeDefined();
    expect(message.apns.payload.aps.sound).toBe("default");
    expect(message.apns.payload.aps).not.toHaveProperty("badge");
  });
});
