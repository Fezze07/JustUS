const express = require("express");
const { AppError } = require("../all_imports");

const pingRoutes = require("./ping");
const authRoutes = require("../features/auth/auth.routes");
const notifyRoutes = require("../features/notifications/notify.routes");
const versionRoutes = require("./version");
const mediaRoutes = require("../features/media/media.routes");
const aiRoutes = require("../features/ai/ai.routes");
const userRoutes = require("../features/user/user.routes");

const router = express.Router();

router.use("/", pingRoutes);
router.use("/auth", authRoutes);
router.use("/app-version", versionRoutes);
router.use("/media", mediaRoutes);
router.use("/ai", aiRoutes);
router.use("/notify", notifyRoutes);
router.use("/users", userRoutes);

router.use((_req, _res, next) => {
  next(new AppError({ errorKey: "API_NOT_FOUND_001" }));
});

module.exports = router;
