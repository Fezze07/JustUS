const roleCapabilities = {
  guest: [],
  user: [
    "can_media_upload",
    "can_profile_update"
  ],
  premium: [
    "can_media_upload",
    "can_profile_update",
    "can_upload_large",
  ],
  moderator: [
    "can_media_upload",
    "can_profile_update",
    "can_moderate_content",
  ],
  system: [
    "can_media_upload",
    "can_profile_update",
    "can_upload_large",
    "can_system_access",
  ],
};

function normalizeRole(role) {
  const value = String(role ?? "guest").trim().toLowerCase();
  return roleCapabilities[value] ? value : "guest";
}

function normalizeCapabilities(input) {
  if (Array.isArray(input)) {
    return input.map((value) => String(value).trim()).filter(Boolean);
  }

  if (typeof input === "string") {
    return input
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
  }

  return [];
}

function resolveCapabilities(role, customCapabilities) {
  const normalizedRole = normalizeRole(role);
  const defaults = roleCapabilities[normalizedRole] ?? roleCapabilities.user;
  const merged = new Set([...defaults, ...normalizeCapabilities(customCapabilities)]);
  return Array.from(merged);
}

function hasCapability(capabilities, requiredCapability) {
  return Array.isArray(capabilities) && capabilities.includes(requiredCapability);
}

module.exports = {
  normalizeRole,
  normalizeCapabilities,
  resolveCapabilities,
  hasCapability,
};
