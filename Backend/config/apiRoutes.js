const API_PREFIX = "/api";
const API_V1_PREFIX = `${API_PREFIX}/v1`;

const CALLBACK_ROUTES = {
  auth: "/auth/callback",
  invite: "/auth/invite-callback",
};

const API_V1_PATHS = {
  root: API_V1_PREFIX,
  ping: `${API_V1_PREFIX}/ping`,
  authBase: `${API_V1_PREFIX}/auth`,
  mediaBase: `${API_V1_PREFIX}/media`,
  aiBase: `${API_V1_PREFIX}/ai`,
  notifyBase: `${API_V1_PREFIX}/notify`,
  usersBase: `${API_V1_PREFIX}/users`,
  appVersion: `${API_V1_PREFIX}/app-version`,
  authRefresh: `${API_V1_PREFIX}/auth/refresh`,
  authLoginAttempt: `${API_V1_PREFIX}/auth/login-attempt`,
  authLoginRiskCheck: `${API_V1_PREFIX}/auth/login-risk-check`,
  authSessionSync: `${API_V1_PREFIX}/auth/session-sync`,
  authInvite: `${API_V1_PREFIX}/auth/invite`,
  authDeviceToken: `${API_V1_PREFIX}/auth/device-token`,
  aiQuestion: `${API_V1_PREFIX}/ai/question`,
  mediaFile: `${API_V1_PREFIX}/media/file`,
  userWipe: `${API_V1_PREFIX}/users/wipe`,
};

module.exports = {
  API_PREFIX,
  API_V1_PREFIX,
  CALLBACK_ROUTES,
  API_V1_PATHS,
};
