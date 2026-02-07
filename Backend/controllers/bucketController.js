const db = require('../config/db');
const { getPartnerId } = require("../utils/partnershipUtils");

module.exports = {
    getAll: async (req, res) => {
        try {
            const [rows] = await db.query(
                `SELECT * FROM bucket_items WHERE user_id = ? OR partner_id = ? ORDER BY created_at DESC`,
                [req.user.id, req.user.id]
            );
            res.json({ success: true, items: rows });
        } catch (err) {
            res.status(500).json({ success: false, error: "Server error" });
        }
    },

    addItem: async (req, res) => {
        try {
            const { text } = req.body;
            const userId = req.user?.id;
            const partnerId = await getPartnerId(req.user.id);
            if (!partnerId) return res.status(400).json({ success: false, error: "Nessun partner collegato" });
            if (!text || !partnerId || !userId) {
                return res.status(400).json({ success: false, error: "Missing text or partnerId" });
            }
            await db.query(
                `INSERT INTO bucket_items (user_id, partner_id, text) VALUES (?, ?, ?)`, [userId, partnerId, text] );
            res.json({ success: true });
        } catch (err) {
            console.error("💥 ERRORE addItem:", err);
            res.status(500).json({ success: false, error: "Server error" });
        }
    },
    
    toggleDone: async (req, res) => {
        try {
            const { id } = req.params;
            await db.query(
                `UPDATE bucket_items SET done = NOT done WHERE id = ? AND (user_id = ? OR partner_id = ?)`,
                [id, req.user.id, req.user.id]
            );
            res.json({ success: true });
        } catch (err) {
            res.status(500).json({ success: false, error: "Server error" });
        }
    },

    deleteItem: async (req, res) => {
        try {
            const { id } = req.params;
            await db.query(
                `DELETE FROM bucket_items WHERE id = ? AND (user_id = ? OR partner_id = ?)`,
                [id, req.user.id, req.user.id]
            );
            res.json({ success: true });
        } catch (err) {
            res.status(500).json({ success: false, error: "Server error" });
        }
    }
}