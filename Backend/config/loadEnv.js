const path = require("path");
const dotenv = require("dotenv");

let loaded = false;

function resolveEnvFile() {
  if (process.env.JUSTUS_ENV_FILE) {
    return process.env.JUSTUS_ENV_FILE;
  }

  if (process.env.ENV === "test" || process.env.NODE_ENV === "test") {
    return ".env.test";
  }

  return ".env";
}

function loadEnv() {
  if (loaded) {
    return;
  }

  const envFile = resolveEnvFile();

  dotenv.config({
    path: path.isAbsolute(envFile)
      ? envFile
      : path.join(__dirname, "../../", envFile),
    quiet: true,
  });

  loaded = true;
}

module.exports = {
  loadEnv,
  resolveEnvFile,
};