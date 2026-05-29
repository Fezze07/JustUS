const express = require("express");
const { asyncHandler, getLatestAppVersion } = require("../all_imports");
const router = express.Router();

router.get("/", asyncHandler(async (_req, res) => {
  const latest = await getLatestAppVersion();
  return res.json(latest);
}));

module.exports = router;
