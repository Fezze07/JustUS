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

  if (!parsed?.version) {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Versione app non trovata",
    });
  }

  return {
    version: parsed.version,
    build: parsed.build,
    apk_url: parsed.apk_url,
    changelog: parsed.changelog,
  };
}

async function getLatestAppApk() {
  const apkPath = path.join(DATA_DIR, "versions", "apk", "justus.apk");

  try {
    await fs.access(apkPath);
  } catch (error) {
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "APK non disponibile",
      cause: error,
    });
  }

  return apkPath;
}

module.exports = {
  getLatestAppVersion,
  getLatestAppApk,
};