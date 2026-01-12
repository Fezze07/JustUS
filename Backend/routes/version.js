const express = require("express");
const path = require("path");
const fs = require("fs");
const router = express.Router();

// GET /app-version
router.get("/", (req, res) => {
    const filePath = path.join(__dirname, "../versions/app_version.json");
    fs.readFile(filePath, "utf8", (err, data) => {
        if (err) {
            console.error("Errore leggendo app_version.json:", err);
            return res.status(500).json({ error: "Impossibile leggere versione app" });
        }
        try {
            const json = JSON.parse(data);
            // Prendi solo l'ultima versione
            const latest = json.versions[json.versions.length - 1];
            return res.json({
                version: latest.version,
                apk_url: latest.apk_url,
                changelog: latest.changelog
            });
        } catch (parseErr) {
            console.error("Errore parsing JSON:", parseErr);
            return res.status(500).json({ error: "JSON non valido" });
        }
    });
});

module.exports = router;