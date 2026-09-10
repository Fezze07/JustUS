const express = require("express");
const {
  asyncHandler,
  getLatestAppVersion,
  getLatestAppApk,
} = require("../all_imports");
const router = express.Router();

router.get("/", asyncHandler(async (_req, res) => {
  const latest = await getLatestAppVersion();
  return res.json(latest);
}));

router.get("/download", asyncHandler(async (_req, res) => {
  const apkPath = await getLatestAppApk();
  return res.download(apkPath, "justus.apk");
}));

module.exports = router;
