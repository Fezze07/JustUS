const path = require("path");
const fs = require("fs").promises;
const { AppError } = require("../all_imports");

async function getLatestAppVersion() {
  const filePath = path.join(__dirname, "../versions/app_version.json");
  let rawData;

  try {
    rawData = await fs.readFile(filePath, "utf8");
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

  const versions = Array.isArray(parsed?.versions) ? parsed.versions : [];
  const latest = versions[versions.length - 1];

  if (!latest) {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Versione app non trovata",
    });
  }

  return {
    version: latest.version,
    apk_url: latest.apk_url,
    changelog: latest.changelog,
  };
}

module.exports = {
  getLatestAppVersion,
};
