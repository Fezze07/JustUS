const express = require("express");
const router = express.Router();
const { registerUser, loginUser, requestUserCodes, updateDeviceToken } = require("../controllers/authController");
const { loginLimiter, requestCodeLimiter, registerLimiter } = require("../middleware/rateLimit");

router.post("/register", registerLimiter, registerUser);
router.post("/login", loginLimiter, loginUser);
router.post("/request-code", requestCodeLimiter, requestUserCodes);
router.post("/device-token", updateDeviceToken);

module.exports = router;