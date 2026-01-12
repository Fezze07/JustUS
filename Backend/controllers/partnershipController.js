const pool = require("../config/db");

// ---------- INVIO RICHIESTA ----------
async function sendPartnerRequest(req, res) {
    try {
        const requester_id = req.user.id;
        const { partner_username, partner_code } = req.body;
        if (!partner_username || !partner_code) return res.status(400).json({ success: false, error: "Dati mancanti" });
        const [partnerRows] = await pool.query(
            "SELECT id FROM users WHERE username = ? AND code = ?",
            [partner_username, partner_code]
        );
        if (!partnerRows.length) return res.status(404).json({ success: false, error: "Partner non trovato" });
        const partner_id = partnerRows[0].id;
        const [existing] = await pool.query(
            "SELECT id FROM partnerships WHERE (user_id = ? OR partner_id = ?) AND status = 'accepted'",
            [requester_id, requester_id]
        );
        if (existing.length) return res.status(400).json({ success: false, error: "Hai già un partner" });
        const [pending] = await pool.query(
            "SELECT id FROM partnerships WHERE user_id = ? AND partner_id = ? AND status = 'pending'",
            [requester_id, partner_id]
        );
        if (pending.length) return res.status(400).json({ success: false, error: "Richiesta già inviata" });
        await pool.query("INSERT INTO partnerships (user_id, partner_id) VALUES (?, ?)", [requester_id, partner_id]);
        res.json({ success: true, message: "Richiesta inviata" });
    } catch (err) { console.error(err); res.status(500).json({ success: false, error: "Server error" }); }
}

// ---------- ACCETTA RICHIESTA ----------
async function acceptPartnerRequest(req, res) {
    try {
        const partner_id = req.user.id;
        const { requester_id } = req.body;
        if (!requester_id) return res.status(400).json({ success: false, error: "Dati mancanti" });
        const [rows] = await pool.query(
            "SELECT id FROM partnerships WHERE user_id = ? AND partner_id = ? AND status = 'pending'",
            [requester_id, partner_id]
        );
        if (!rows.length) return res.status(404).json({ success: false, error: "Richiesta non trovata" });
        await pool.query("UPDATE partnerships SET status = 'accepted' WHERE id = ?", [rows[0].id]);
        res.json({ success: true, message: "Partnership accettata" });
    } catch (err) { console.error(err); res.status(500).json({ success: false, error: "Server error" }); }
}

// ---------- RIFIUTA RICHIESTA ----------
async function rejectPartnerRequest(req, res) {
    try {
        const partner_id = req.user.id;
        const { requester_id } = req.body;
        if (!requester_id) return res.status(400).json({ success: false, error: "Dati mancanti" });
        const [rows] = await pool.query(
            "SELECT id FROM partnerships WHERE user_id = ? AND partner_id = ? AND status = 'pending'",
            [requester_id, partner_id]
        );
        if (!rows.length) return res.status(404).json({ success: false, error: "Richiesta non trovata" });
        await pool.query("DELETE FROM partnerships WHERE id = ?", [rows[0].id]);
        res.json({ success: true, message: "Richiesta rifiutata" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, error: "Server error" });
    }
}

// ---------- OTTIENI PARTNER ----------
async function getPartnership(req, res) {
    try {
        const user_id = req.user.id;
        const [accepted] = await pool.query(
            `SELECT u.id, u.username, u.code, u.bio, u.profile_pic_url
             FROM partnerships p
             JOIN users u ON u.id = IF(p.user_id = ?, p.partner_id, p.user_id)
             WHERE (p.user_id = ? OR p.partner_id = ?) AND p.status = 'accepted' LIMIT 1`,
            [user_id, user_id, user_id]
        );
        const [received] = await pool.query(
            `SELECT u.id, u.username, u.code
             FROM partnerships p
             JOIN users u ON u.id = p.user_id
             WHERE p.partner_id = ? AND p.status = 'pending'`,
            [user_id]
        );
        const [sent] = await pool.query(
            `SELECT u.id, u.username, u.code
             FROM partnerships p
             JOIN users u ON u.id = p.partner_id
             WHERE p.user_id = ? AND p.status = 'pending'`,
            [user_id]
        );
        res.json({ success: true, partner: accepted[0] || null, pendingRequests: { received, sent } });
    } catch (err) { console.error(err); res.status(500).json({ success: false, error: "Server error" }); }
}

// ---------- CERCA PARTNER ----------
async function searchPartner(req, res) {
    try {
        let { username, code } = req.query;
        username = username?.trim();
        code = code?.trim();
        if (!username && !code) return res.json({ success: true, users: [] });
        let query = `SELECT id, username, code, profile_pic_url FROM users WHERE 1=1`;
        const params = [];
        if (username) {
            query += ` AND username LIKE ?`;
            params.push(`%${username}%`);
        }
        if (code) {
            query += ` AND code LIKE ?`;
            params.push(`${code}%`);
        }
        query += ` LIMIT 20`;
        const [rows] = await pool.query(query, params);
        res.json({ success: true, users: rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, error: "Server error" });
    }
}

module.exports = { sendPartnerRequest, acceptPartnerRequest, rejectPartnerRequest, getPartnership, searchPartner };