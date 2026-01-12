const express = require("express");
const router = express.Router();
const { generateQuestion, saveAnswer, getStats } = require("../controllers/gameController");

router.get("/new", generateQuestion);
router.post("/answer", saveAnswer);
router.get("/stats", getStats);

module.exports = router;