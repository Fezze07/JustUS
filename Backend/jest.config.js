module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/../test/backend"],
  clearMocks: true,
  restoreMocks: true,
  setupFiles: ["<rootDir>/../test/backend/setupEnv.js"],
  moduleDirectories: ["node_modules", "<rootDir>/node_modules"],
};
