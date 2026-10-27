const express = require("express");
const { authenticated } = require("../../core/auth/auth.middleware");
const { limited } = require("../../core/rateLimit");
const { signed } = require("../../core/security/signed.middleware");
const { validated } = require("../../core/validation/validate.middleware");
const { acceptCancelSchema } = require("./partnership.schemas");
const { acceptCancellation } = require("./partnership.controller");

const router = express.Router();

router.post(
  "/cancel/accept",
  authenticated(),
  limited(),
  signed("partnership-cancel-accept"),
  validated({ body: acceptCancelSchema }),
  acceptCancellation
);

module.exports = router;
