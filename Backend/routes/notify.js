const express = require("express");
const router = express.Router();
const { sendNotificationController } = require("../controllers/notifyController");
const authenticateToken = require('../middleware/authMiddleware');

router.post("/:type", authenticateToken, sendNotificationController);
router.post("/partner", authenticateToken, sendNotificationController);

module.exports = router;