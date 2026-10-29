jest.mock("../all_imports", () => ({
  adminSupabase: { from: jest.fn() },
  assertDbSuccess: ({ data, error }) => {
    if (error) throw new Error(error.message);
    return data;
  },
}));

const { adminSupabase } = require("../all_imports");
const {
  getPartnershipId,
  isPartnershipMember,
} = require("../utils/misc/partnershipUtils");

const makeBuilder = (result) => {
  const builder = {
    select: jest.fn(() => builder),
    or: jest.fn(() => builder),
    eq: jest.fn(() => builder),
    order: jest.fn(() => builder),
    limit: jest.fn(() => builder),
    maybeSingle: jest.fn().mockResolvedValue(result),
  };
  return builder;
};

describe("partnershipUtils media lookups", () => {
  beforeEach(() => {
    adminSupabase.from.mockReset();
  });

  test("getPartnershipId prefers an accepted partnership", async () => {
    const accepted = makeBuilder({ data: { id: 5 }, error: null });
    adminSupabase.from.mockReturnValueOnce(accepted);

    await expect(getPartnershipId(42)).resolves.toBe(5);
    expect(adminSupabase.from).toHaveBeenCalledWith("partnerships");
    expect(accepted.eq).toHaveBeenCalledWith("status", "accepted");
    expect(accepted.or).toHaveBeenCalledWith(
      "user_id_1.eq.42,user_id_2.eq.42"
    );
    expect(accepted.maybeSingle).toHaveBeenCalledTimes(1);
  });

  test("getPartnershipId falls back to a cancelled partnership", async () => {
    const accepted = makeBuilder({ data: null, error: null });
    const cancelled = makeBuilder({ data: { id: 9 }, error: null });
    adminSupabase.from
      .mockReturnValueOnce(accepted)
      .mockReturnValueOnce(cancelled);

    await expect(getPartnershipId(42)).resolves.toBe(9);
    expect(cancelled.eq).toHaveBeenCalledWith("status", "cancelled");
  });

  test("getPartnershipId returns null when the user has no partnership", async () => {
    adminSupabase.from.mockImplementation(() =>
      makeBuilder({ data: null, error: null })
    );

    await expect(getPartnershipId(42)).resolves.toBeNull();
    expect(adminSupabase.from).toHaveBeenCalledTimes(2);
  });

  test("isPartnershipMember requires an accepted partnership and membership", async () => {
    const query = makeBuilder({ data: { id: 5 }, error: null });
    adminSupabase.from.mockReturnValue(query);

    await expect(isPartnershipMember(5, 42)).resolves.toBe(true);
    expect(query.eq).toHaveBeenCalledWith("id", 5);
    expect(query.eq).toHaveBeenCalledWith("status", "accepted");
    expect(query.or).toHaveBeenCalledWith("user_id_1.eq.42,user_id_2.eq.42");
  });

  test("isPartnershipMember rejects a partnership the user does not belong to", async () => {
    adminSupabase.from.mockReturnValue(
      makeBuilder({ data: null, error: null })
    );

    await expect(isPartnershipMember(5, 42)).resolves.toBe(false);
  });
});
