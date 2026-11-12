jest.mock("../all_imports", () => {
  const { AppError } = require("../core/errors/AppError");
  return {
    AppError,
    adminSupabase: { from: jest.fn(), rpc: jest.fn() },
    assertDbSuccess: ({ data, error }, errorKey = "DB_READ_001") => {
      if (error) {
        throw new AppError({ errorKey, message: error.message, cause: error });
      }
      return data;
    },
  };
});

const { adminSupabase } = require("../all_imports");
const {
  getPartnerId,
  getCancellationPartnerId,
  getPartnershipId,
  getPartnershipById,
  isPartnershipParticipant,
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

describe("partnershipUtils lookups", () => {
  beforeEach(() => {
    adminSupabase.from.mockReset();
    adminSupabase.rpc.mockReset();
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

  test("getPartnershipById returns the row the cancellation flow needs", async () => {
    const row = {
      id: 5,
      user_id_1: 42,
      user_id_2: 77,
      status: "cancelled",
      cancel_requested_by: 42,
      cancel_expires_at: "2026-11-01T00:00:00Z",
    };
    const query = makeBuilder({ data: row, error: null });
    adminSupabase.from.mockReturnValue(query);

    await expect(getPartnershipById(5)).resolves.toEqual(row);
    expect(query.select).toHaveBeenCalledWith(
      "id, user_id_1, user_id_2, status, cancel_requested_by, cancel_expires_at"
    );
    expect(query.eq).toHaveBeenCalledWith("id", 5);
  });

  test("getPartnershipById returns null for a missing row", async () => {
    adminSupabase.from.mockReturnValueOnce(
      makeBuilder({ data: null, error: null })
    );

    await expect(getPartnershipById(404)).resolves.toBeNull();
  });

  test("getPartnershipById surfaces a read error as DB-READ-001", async () => {
    adminSupabase.from.mockReturnValueOnce(
      makeBuilder({ data: null, error: { message: "db down" } })
    );

    await expect(getPartnershipById(5)).rejects.toMatchObject({
      code: "DB-READ-001",
      message: "db down",
    });
  });

  test("getPartnerId returns the accepted partner id or null", async () => {
    adminSupabase.rpc
      .mockResolvedValueOnce({ data: [{ id: 77 }], error: null })
      .mockResolvedValueOnce({ data: [], error: null });

    await expect(getPartnerId(42)).resolves.toBe(77);
    await expect(getPartnerId(42)).resolves.toBeNull();
    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "partnership_get_accepted_partner",
      { target_user_id: 42 }
    );
  });

  test("getPartnerId surfaces a read error as DB-READ-001", async () => {
    adminSupabase.rpc.mockResolvedValueOnce({
      data: null,
      error: { message: "accepted partner lookup down" },
    });

    await expect(getPartnerId(42)).rejects.toMatchObject({
      code: "DB-READ-001",
    });
  });

  test("getCancellationPartnerId returns the cancellation partner or null", async () => {
    adminSupabase.rpc
      .mockResolvedValueOnce({ data: [{ partner_id: 77 }], error: null })
      .mockResolvedValueOnce({ data: null, error: null });

    await expect(getCancellationPartnerId(42)).resolves.toBe(77);
    await expect(getCancellationPartnerId(42)).resolves.toBeNull();
    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "partnership_get_cancellation_partner",
      { p_user_id: 42 }
    );
  });

  test("getCancellationPartnerId surfaces a read error as DB-READ-001", async () => {
    adminSupabase.rpc.mockResolvedValueOnce({
      data: null,
      error: { message: "cancellation partner lookup down" },
    });

    await expect(getCancellationPartnerId(42)).rejects.toMatchObject({
      code: "DB-READ-001",
    });
  });

  test("isPartnershipParticipant checks both member columns", () => {
    expect(
      isPartnershipParticipant({ user_id_1: 42, user_id_2: 77 }, 42)
    ).toBe(true);
    expect(
      isPartnershipParticipant({ user_id_1: 42, user_id_2: 77 }, 77)
    ).toBe(true);
    expect(
      isPartnershipParticipant({ user_id_1: 42, user_id_2: 77 }, 99)
    ).toBe(false);
    expect(isPartnershipParticipant(null, 42)).toBe(false);
  });

  test("isPartnershipMember requires an accepted partnership and membership", async () => {
    const query = makeBuilder({
      data: { user_id_1: 42, user_id_2: 77 },
      error: null,
    });
    adminSupabase.from.mockReturnValue(query);

    await expect(isPartnershipMember(5, 42)).resolves.toBe(true);
    expect(query.select).toHaveBeenCalledWith("user_id_1, user_id_2");
    expect(query.eq).toHaveBeenCalledWith("id", 5);
    expect(query.eq).toHaveBeenCalledWith("status", "accepted");
    expect(query.or).not.toHaveBeenCalled();
  });

  test("isPartnershipMember rejects a partnership the user does not belong to", async () => {
    adminSupabase.from.mockReturnValue(
      makeBuilder({
        data: { user_id_1: 42, user_id_2: 77 },
        error: null,
      })
    );

    await expect(isPartnershipMember(5, 99)).resolves.toBe(false);
  });
});
