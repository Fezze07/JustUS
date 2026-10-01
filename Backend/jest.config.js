module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/test"],
  clearMocks: true,
  restoreMocks: true,
  setupFiles: ["<rootDir>/test/setupEnv.js"],
  moduleDirectories: ["node_modules", "<rootDir>/node_modules"],
  // test/mock-ai is a standalone helper service, not a Jest suite.
  testPathIgnorePatterns: ["<rootDir>/node_modules/", "<rootDir>/test/mock-ai/"],
  coveragePathIgnorePatterns: ["<rootDir>/test/mock-ai/"],
};
