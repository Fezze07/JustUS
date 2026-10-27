const express = require("express");
const { chain, authenticated, signed, validated, limited } = require("../../routes/routeHelpers");
const { createIpUserRateLimit } = require("../../utils/auth/rateLimitPresets");
const { acceptCancelSchema } = require("./partnership.schemas");
const { acceptCancellation } = require("./partnership.controller");

const router = express.Router();

const cancelRateLimit = createIpUserRateLimit({
  name: "partnership.cancel.accept",
  message: "Too many cancellation requests",
  ipMax: 30,
  userMax: 10,
});

router.post(
  "/cancel/accept",
  ...chain(
    authenticated(),
    limited(cancelRateLimit),
    signed("partnership-cancel-accept"),
    validated({ body: acceptCancelSchema })
  ),
  acceptCancellation
);

module.exports = router;
