// In-memory stand-in for the `user_devices` table so the delete predicate can be
// exercised as behaviour (a filtered delete), not as a mocked call chain.
const mockDb = { rows: [] };

const mockQueryBuilder = (table) => {
  const filters = { eq: [], in: [] };
  const builder = {
    delete: () => builder,
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
      const deleted = mockDb.rows.filter(matches);
      mockDb.rows = mockDb.rows.filter((row) => !matches(row));
      resolve({ data: deleted, error: null });
    },
  };
  return builder;
};

jest.mock("../all_imports", () => ({
  adminSupabase: { from: (table) => mockQueryBuilder(table) },
  assertDbSuccess: (result) => {
    if (result?.error) throw new Error(result.error.message ?? "db error");
    return result?.data ?? null;
  },
}));

const { deleteInvalidTokens } = require("../features/notifications/notification.service");

beforeEach(() => {
  mockDb.rows = [];
});

describe("deleteInvalidTokens user scoping", () => {
  test("leaves a token reassigned to another user untouched", async () => {
    const row = { id: 1, user_id: 2, device_token: "tok-shared" };
    mockDb.rows = [{ ...row }];

    const removed = await deleteInvalidTokens(1, ["tok-shared"]);

    expect(removed).toBe(1);
    expect(mockDb.rows).toEqual([row]);
  });

  test("deletes the row when the token still belongs to the caller", async () => {
    mockDb.rows = [
      { id: 1, user_id: 1, device_token: "tok-mine" },
      { id: 2, user_id: 2, device_token: "tok-other" },
    ];

    await deleteInvalidTokens(1, ["tok-mine"]);

    expect(mockDb.rows).toEqual([{ id: 2, user_id: 2, device_token: "tok-other" }]);
  });

  test("returns 0 without querying when every token is falsy", async () => {
    expect(await deleteInvalidTokens(1, [])).toBe(0);
    expect(await deleteInvalidTokens(1, [null, undefined, ""])).toBe(0);
  });
});
