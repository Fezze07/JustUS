const pool = require("../config/db");
const { getPartnerId } = require("../utils/partnershipUtils");

async function sendMissYou(req, res) {
    try {
        const senderId = req.user.id;
        const receiverId = await getPartnerId(senderId);
        if (!receiverId)
            return res.status(400).json({ error: "Nessun partner collegato" });
        await pool.query(
            "INSERT INTO missyou (sender_id, receiver_id) VALUES (?, ?)", [senderId, receiverId] );
        const [totalResult] = await pool.query(
            "SELECT COUNT(*) AS total FROM missyou WHERE sender_id = ? AND receiver_id = ?", [senderId, receiverId] );
        res.json({ success: true, total: totalResult[0].total });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error" });
    }
}

async function getMissYouTotal(req, res) {
    try {
        const senderId = req.user.id;
        const receiverId = await getPartnerId(senderId);
        if (!receiverId)
            return res.status(400).json({ error: "Nessun partner collegato" });
        const [totalResult] = await pool.query(
            "SELECT COUNT(*) AS total FROM missyou WHERE sender_id = ? AND receiver_id = ?", [senderId, receiverId] );
        res.json({ success: true, total: totalResult[0].total });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error" });
    }
}

module.exports = { sendMissYou, getMissYouTotal };