const { createClient } = require("@supabase/supabase-js");
const { env, requireEnv } = require("./env");

requireEnv(["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"], "Supabase admin client");

const createBaseClient = (key, options = {}) => createClient(
  env.supabaseUrl,
  key,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    ...options
  }
);

const adminSupabase = createBaseClient(env.supabaseServiceRoleKey);

const authSupabase = createBaseClient(env.supabaseAnonKey || env.supabaseServiceRoleKey);

function createUserScopedClient(accessToken) {
  return createBaseClient(
    env.supabaseAnonKey || env.supabaseServiceRoleKey,
    accessToken ? {
      global: {
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    } : {}
  );
}

module.exports = {
  adminSupabase,
  authSupabase,
  createUserScopedClient,
};
