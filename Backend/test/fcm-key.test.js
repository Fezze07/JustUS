const fs = require("fs");
const path = require("path");

const dataDir = path.join(__dirname, "..", "test-data");
const relativeFixture = path.join(dataDir, "fcm-relative.test.json");
const absoluteFixture = path.join(dataDir, "fcm-absolute.test.json");
const account = {
  project_id: "justus-test",
  private_key: "test-key",
  client_email: "fcm@test.local",
};

const mockCert = jest.fn(() => "credential");
const mockInitializeApp = jest.fn();

jest.mock("firebase-admin", () => ({
  apps: [],
  cert: (...args) => mockCert(...args),
  initializeApp: (...args) => mockInitializeApp(...args),
}));

jest.mock("firebase-admin/messaging", () => ({
  getMessaging: jest.fn(),
}));

const originalPath = process.env.FCM_SERVICE_ACCOUNT_PATH;
let initializeFirebaseAdmin;

beforeEach(() => {
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(relativeFixture, JSON.stringify(account));
  fs.writeFileSync(absoluteFixture, JSON.stringify(account));
  jest.resetModules();
  ({ initializeFirebaseAdmin } = require("../config/fcm-key"));
});

afterEach(() => {
  fs.rmSync(relativeFixture, { force: true });
  fs.rmSync(absoluteFixture, { force: true });
  if (originalPath === undefined) {
    delete process.env.FCM_SERVICE_ACCOUNT_PATH;
  } else {
    process.env.FCM_SERVICE_ACCOUNT_PATH = originalPath;
  }
});

test("resolves a relative service-account path from the Backend root", () => {
  process.env.FCM_SERVICE_ACCOUNT_PATH = "./test-data/fcm-relative.test.json";

  expect(initializeFirebaseAdmin()).toBe(true);
  expect(mockCert).toHaveBeenCalledWith(account);
  expect(mockInitializeApp).toHaveBeenCalled();
});

test("keeps an absolute service-account path", () => {
  process.env.FCM_SERVICE_ACCOUNT_PATH = absoluteFixture;

  expect(initializeFirebaseAdmin()).toBe(true);
  expect(mockCert).toHaveBeenCalledWith(account);
});
