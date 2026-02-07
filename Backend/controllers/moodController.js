const pool = require("../config/db");
const { getPartnerId } = require("../utils/partnershipUtils");

const setMood = async (req, res) => {
    try {
        const { emoji } = req.body;
        if (!emoji) {
            return res.status(400).json({ success: false, error: "Emoji mancante" });
        }
        await pool.query(
            "INSERT INTO moods (user_id, emoji) VALUES (?, ?)", [req.user.id, emoji] );
        res.json({ success: true, emoji });
    } catch (err) {
        console.error("ERRORE setMood:", err);
        res.status(500).json({ success: false, error: "Server error" });
    }
};

const getMood = async (req, res) => {
    try {
        const userId = req.user.id;
        const target = req.query.target;
        let targetId = userId;
        if (target === "partner") {
            targetId = await getPartnerId(userId);
            if (!targetId) {
                return res.status(400).json({ success: false, error: "Nessun partner collegato" });
            }
        }
        const [rows] = await pool.query(
            "SELECT emoji FROM moods WHERE user_id = ? ORDER BY created_at DESC LIMIT 1", [targetId] );
        res.json({ success: true, emoji: rows.length ? rows[0].emoji : null });
    } catch (err) {
        console.error("ERRORE getMood:", err);
        res.status(500).json({ success: false, error: "Server error" });
    }
};

// Prendi le ultime 4 emoji tra utente e partner
const getRecentCoupleEmojis = async (req, res) => {
    try {
        const userId = req.user.id;
        const partnerId = await getPartnerId(userId);
        if (!partnerId) {
            return res.status(400).json({ msuccess: false, error: "Nessun partner collegato" });
        }
        const [rows] = await pool.query(
            `SELECT emoji FROM moods WHERE user_id IN (?, ?) ORDER BY created_at DESC LIMIT 4`, [userId, partnerId] );
        res.json({ success: true, emojis: rows.map(r => r.emoji) });
    } catch (err) {
        console.error("ERRORE getRecentCoupleEmojis:", err);
        res.status(500).json({ success: false, error: "Server error" });
    }
};

module.exports = { setMood, getMood, getRecentCoupleEmojis };