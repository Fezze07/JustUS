module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/test"],
  clearMocks: true,
  restoreMocks: true,
  setupFiles: ["<rootDir>/test/setupEnv.js"],
  moduleDirectories: ["node_modules", "<rootDir>/node_modules"],
};
