const express = require("express");
const router = express.Router();

router.get("/", (req, res) => {
    res.send("Server JustUS attivo! 🟢");
});

router.get("/ping", (req, res) => {
    res.json({ status: "ok" });
});

module.exports = router;
