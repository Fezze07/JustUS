function createQueryBuilder(overrides = {}) {
  const builder = {
    select: jest.fn(() => builder),
    insert: jest.fn(() => builder),
    update: jest.fn(() => builder),
    delete: jest.fn(() => builder),
    upsert: jest.fn().mockResolvedValue({ data: null, error: null }),
    eq: jest.fn(() => builder),
    neq: jest.fn(() => builder),
    or: jest.fn(() => builder),
    order: jest.fn(() => builder),
    limit: jest.fn(() => builder),
    maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
    single: jest.fn().mockResolvedValue({ data: null, error: null }),
    ...overrides,
  };

  return builder;
}

module.exports = {
  createQueryBuilder,
};
