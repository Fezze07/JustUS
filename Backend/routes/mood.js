const express = require("express");
const router = express.Router();
const { setMood, getMood, getRecentCoupleEmojis } = require("../controllers/moodController");
const authenticateToken = require('../middleware/authMiddleware');

router.post("/", authenticateToken, setMood);
router.get("/", authenticateToken, getMood);
router.get("/recent/couple", authenticateToken, getRecentCoupleEmojis);

module.exports = router;