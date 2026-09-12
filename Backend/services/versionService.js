const path = require("path");
const fs = require("fs").promises;

const { AppError } = require("../all_imports");

const DATA_DIR = process.env.JUSTUS_DATA_DIR || "/var/www/justus/JustUS-Data";
const VERSION_FILE = path.join(DATA_DIR, "versions", "app_version.json");

async function getLatestAppVersion() {
  let rawData;

  try {
    rawData = await fs.readFile(VERSION_FILE, "utf8");
  } catch (error) {
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "Impossibile leggere versione app",
      cause: error,
    });
  }

  let parsed;

  try {
    parsed = JSON.parse(rawData);
  } catch (error) {
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "JSON non valido",
      cause: error,
    });
  }

  if (!parsed?.version || !parsed?.apk_url) {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Metadati versione app incompleti",
    });
  }

  if (typeof parsed.build !== "number") {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Build versione app non valida",
    });
  }

  return {
    version: parsed.version,
    build: parsed.build,
    min_build: typeof parsed.min_build === "number" ? parsed.min_build : 0,
    force_update: parsed.force_update === true,
    apk_url: parsed.apk_url,
    changelog: parsed.changelog || "",
  };
}

module.exports = {
  getLatestAppVersion,
  getLatestAppApk,
};