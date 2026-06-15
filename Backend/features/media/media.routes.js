const express = require("express");
const router = express.Router();
const {
  presignUploadController,
  completeUploadController,
  redirectToSignedDownloadController,
} = require("../../all_imports");
const { createIpUserRateLimit } = require("../../utils/auth/rateLimitPresets");
const {
  chain,
  authenticated,
  capability,
  signed,
  validated,
  limited,
} = require("../../routes/routeHelpers");
const {
  presignSchema,
  completeSchema,
  fileQuerySchema,
} = require("./media.schemas");

const mediaRateLimit = createIpUserRateLimit({
  name: "media",
  message: "Too many media requests",
  ipMax: 60,
  userMax: 40,
});

router.post(
  "/upload-url",
  ...chain(
    authenticated(),
    capability("can_media_upload"),
    limited(mediaRateLimit),
    signed("media-upload-url"),
    validated({ body: presignSchema })
  ),
  presignUploadController
);

router.post(
  "/complete",
  ...chain(
    authenticated(),
    capability("can_media_upload"),
    limited(mediaRateLimit),
    signed("media-complete"),
    validated({ body: completeSchema })
  ),
  completeUploadController
);

router.get(
  "/file",
  ...chain(
    authenticated(),
    limited(mediaRateLimit),
    validated({ query: fileQuerySchema })
  ),
  redirectToSignedDownloadController
);

module.exports = router;
