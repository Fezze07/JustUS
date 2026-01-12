const express = require("express");
const router = express.Router();
const { sendMissYou, getMissYouTotal } = require("../controllers/missyouController");
const authenticateToken = require('../middleware/authMiddleware');

router.post("/", authenticateToken, sendMissYou);
router.get("/total/", authenticateToken, getMissYouTotal);

module.exports = router;