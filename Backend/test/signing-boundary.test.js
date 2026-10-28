const { authenticateToken } = require("../all_imports");

const pingRoutes = require("../routes/ping");
const authRoutes = require("../features/auth/auth.routes");
const versionRoutes = require("../routes/version");
const mediaRoutes = require("../features/media/media.routes");
const notifyRoutes = require("../features/notifications/notify.routes");
const userRoutes = require("../features/user/user.routes");
const partnershipRoutes = require("../features/partnership/partnership.routes");
const v1Routes = require("../routes/v1");

// Every mutating route the API exposes, and the deliberate answer to "is it
// HMAC-signed?". A new mutating route that is not added here fails the test,
// so the signed/unsigned boundary stays a decision instead of an accident.
//
// Keeping this file in lockstep with routes/v1.js is the point: add the route
// and its decision in the same change.
const SIGNING_DECISION = {
  "POST /api/v1/auth/installation-id": {
    namespace: "auth-installation-id",
    authenticated: true,
  },
  "POST /api/v1/auth/installation-id-revoke": {
    namespace: "auth-installation-id-revoke",
    authenticated: true,
  },
  "POST /api/v1/auth/installation-id-revoke-all": {
    namespace: "auth-installation-id-revoke-all",
    authenticated: true,
  },
  "POST /api/v1/auth/invite": {
    namespace: "auth-invite",
    authenticated: true,
  },
  "POST /api/v1/auth/invite-user": {
    namespace: "auth-invite-user",
    authenticated: true,
  },
  "POST /api/v1/auth/login-risk-check": {
    namespace: null,
    authenticated: false,
    reason: "Pre-auth by necessity: it runs before a session exists (9.5).",
  },
  "POST /api/v1/auth/login-attempt": {
    namespace: null,
    authenticated: false,
    reason: "Pre-auth by necessity: it runs before a session exists (9.5).",
  },
  "POST /api/v1/auth/session-bind": {
    namespace: null,
    authenticated: true,
    reason:
      "Uses freshNonce instead: it is the call that creates the binding secret HMAC needs.",
  },
  "POST /api/v1/media/upload-url": {
    namespace: "media-upload-url",
    authenticated: true,
  },
  "POST /api/v1/media/complete": {
    namespace: "media-complete",
    authenticated: true,
  },
  "POST /api/v1/media/delete": {
    namespace: "media-delete",
    authenticated: true,
  },
  "POST /api/v1/notify/partner": {
    namespace: "notify-send",
    authenticated: true,
  },
  "POST /api/v1/partnership/cancel/accept": {
    namespace: "partnership-cancel-accept",
    authenticated: true,
  },
  "POST /api/v1/users/wipe": {
    namespace: "user-wipe",
    authenticated: true,
  },
};

const MOUNTS = new Map([
  [pingRoutes, "/api/v1"],
  [authRoutes, "/api/v1/auth"],
  [versionRoutes, "/api/v1/app-version"],
  [mediaRoutes, "/api/v1/media"],
  [notifyRoutes, "/api/v1/notify"],
  [userRoutes, "/api/v1/users"],
  [partnershipRoutes, "/api/v1/partnership"],
]);

const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

function joinPath(prefix, routePath) {
  return `${prefix}${routePath}`.replace(/\/$/, "");
}

// Express 5 dropped the mount string from a `router.use` layer, so the prefix
// comes from MOUNTS keyed by the router object itself. An unmounted router is
// returned as `unknown` and fails the test rather than being skipped.
function collectRoutes(router, prefix, result = { routes: [], unknown: [] }) {
  for (const layer of router.stack) {
    if (layer.route) {
      for (const method of Object.keys(layer.route.methods)) {
        const upper = method.toUpperCase();
        if (!MUTATING_METHODS.has(upper)) continue;

        result.routes.push({
          key: `${upper} ${joinPath(prefix, layer.route.path)}`,
          handlers: layer.route.stack.map((layerStack) => layerStack.handle),
        });
      }
    } else if (layer.name === "router") {
      const mount = MOUNTS.get(layer.handle);
      if (!mount) {
        result.unknown.push(layer);
        continue;
      }
      collectRoutes(layer.handle, mount, result);
    }
  }

  return result;
}

describe("signing boundary", () => {
  const { routes, unknown } = collectRoutes(v1Routes, "/api/v1");

  test("every mounted router is registered in the decision table's mount map", () => {
    expect(unknown).toEqual([]);
  });

  test("the mutating route table and the decision record contain the same routes", () => {
    expect(new Set(routes.map((route) => route.key))).toEqual(
      new Set(Object.keys(SIGNING_DECISION))
    );
  });

  test.each(routes.map((route) => [route.key, route]))(
    "%s matches its recorded signing decision",
    (_key, route) => {
      const decision = SIGNING_DECISION[route.key];
      expect(decision).toBeDefined();

      const namespace =
        route.handlers.map((handler) => handler.namespace).find(Boolean) ?? null;

      expect(namespace).toBe(decision.namespace);
      expect(route.handlers.includes(authenticateToken)).toBe(
        decision.authenticated
      );
      if (namespace === null) {
        expect(decision.reason).toBeTruthy();
      }
    }
  );
});
