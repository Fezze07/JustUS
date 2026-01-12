const pool = require("../config/db");
const { sendNotification } = require("../config/fcm-key");

const sendNotificationController = async (req, res) => {
    try {
        const type = req.params.type || "partner";
        const senderId = req.user.id;
        let receiverId, deviceToken;
        if (type === "partner") {
            const { username, code, title, body } = req.body;
            if (!username || !code || !title || !body) {
                return res.status(400).json({ success: false, error: "Dati mancanti" });
            }
            const [rows] = await pool.query(
                "SELECT id, deviceToken FROM users WHERE username = ? AND code = ?",[username, code]);
            if (!rows.length || !rows[0].deviceToken) {
                return res.status(404).json({ success: false, error: "Receiver non trovato o senza token" });
            }
            receiverId = rows[0].id;
            deviceToken = rows[0].deviceToken;
            await sendNotification(deviceToken, title, body, { type, senderId });
        } else {
            const { receiverId: rid, title, body } = req.body;
            if (!rid || !title || !body) {
                return res.status(400).json({ success: false, error: "Dati mancanti" });
            }
            receiverId = rid;
            const [rows] = await pool.query("SELECT deviceToken FROM users WHERE id = ?", [receiverId]);
            if (!rows.length || !rows[0].deviceToken) {
                return res.status(404).json({ success: false, error: "Receiver senza token" });
            }
            deviceToken = rows[0].deviceToken;
            await sendNotification(deviceToken, title, body, { type, senderId });
        }
        await pool.query(
            `INSERT INTO notifications_logs (sender_id, receiver_id, type)
             VALUES (?, ?, ?)`,
            [senderId, receiverId, type]
        );
        res.json({ success: true });
    } catch (err) {
        console.error("SendNotification error:", err);
        res.status(500).json({ success: false, error: "Server error" });
    }
};

module.exports = { sendNotificationController };