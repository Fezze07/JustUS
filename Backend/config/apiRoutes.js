const API_PREFIX = "/api";
const API_V1_PREFIX = `${API_PREFIX}/v1`;

const API_V1_PATHS = {
  root: API_V1_PREFIX,
  ping: `${API_V1_PREFIX}/ping`,
  authBase: `${API_V1_PREFIX}/auth`,
  mediaBase: `${API_V1_PREFIX}/media`,
  notifyBase: `${API_V1_PREFIX}/notify`,
  usersBase: `${API_V1_PREFIX}/users`,
  partnershipBase: `${API_V1_PREFIX}/partnership`,
  partnershipCancelAccept: `${API_V1_PREFIX}/partnership/cancel/accept`,
  appVersion: `${API_V1_PREFIX}/app-version`,
  authLoginAttempt: `${API_V1_PREFIX}/auth/login-attempt`,
  authLoginRiskCheck: `${API_V1_PREFIX}/auth/login-risk-check`,
  authSessionBind: `${API_V1_PREFIX}/auth/session-bind`,
  authInvite: `${API_V1_PREFIX}/auth/invite`,
  authInstallationId: `${API_V1_PREFIX}/auth/installation-id`,
  authInstallationIdRevoke: `${API_V1_PREFIX}/auth/installation-id-revoke`,
  authInstallationIdRevokeAll: `${API_V1_PREFIX}/auth/installation-id-revoke-all`,
  mediaFile: `${API_V1_PREFIX}/media/file`,
  mediaDelete: `${API_V1_PREFIX}/media/delete`,
  userWipe: `${API_V1_PREFIX}/users/wipe`,
};

module.exports = {
  API_PREFIX,
  API_V1_PREFIX,
  API_V1_PATHS,
};
