const express = require("express");
const router = express.Router();
const authenticateToken = require("../middleware/authMiddleware");
const { sendPartnerRequest, acceptPartnerRequest, rejectPartnerRequest, getPartnership, searchPartner } = require("../controllers/partnershipController");

router.post("/request", authenticateToken, sendPartnerRequest);
router.post("/accept", authenticateToken, acceptPartnerRequest);
router.post("/reject", authenticateToken, rejectPartnerRequest);
router.get("/search", authenticateToken, searchPartner);
router.get("/", authenticateToken, getPartnership);

module.exports = router;