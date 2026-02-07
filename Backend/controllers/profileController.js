const pool = require("../config/db");
const bcrypt = require("bcrypt");
const AUTH_DELAY_MS = 600;
const { getPartnerId } = require("../utils/partnershipUtils");
const { delay, isBlocked, registerFailedLogin, resetLoginFailures } = require('../utils/authUtils');

// ---------- GET PROFILE ----------
exports.getProfile = async (req, res) => {
  try {
    const userId = req.user.id;
    const [users] = await pool.query(
      'SELECT id, username, code, bio, profile_pic_url FROM users WHERE id=?', [userId]
    );
    if (!users.length) return res.status(404).json({ ok:false, msg:"Utente non trovato" });
    const user = users[0];
    res.json({ success: true, profile: user, message: null });
  } catch (err) {
    console.error("GET PROFILE ERROR:", err);
    res.status(500).json({ ok:false, msg:"Errore server" });
  }
};

exports.getPartnerProfile = async (req, res) => {
  try {
    const userId = req.user.id;
    const partnerId = await getPartnerId(userId);
    if (!partnerId) return res.status(404).json({ ok: false, msg: "Nessun partner trovato" });
    const [partnerRows] = await pool.query(
      'SELECT id, username, code, bio, profile_pic_url FROM users WHERE id=?', [partnerId] );
    if (!partnerRows.length) return res.status(404).json({ ok: false, msg: "Profilo partner non trovato" });
    res.json({ success: true, profile: partnerRows[0], message: null });
  } catch (err) {
    console.error("GET PARTNER PROFILE ERROR:", err);
    res.status(500).json({ ok: false, msg: "Errore server" });
  }
};

// ---------- UPDATE PROFILE ----------
exports.updateProfile = async (req, res) => {
  try {
    const userId = req.user.id;
    const { bio, profile_pic_url } = req.body;
    if (bio && bio.length > 255) return res.status(400).json({ ok:false, msg:"Bio troppo lunga" });
    await pool.query(
      "UPDATE users SET bio=COALESCE(?, bio), profile_pic_url=COALESCE(?, profile_pic_url), updated_at=CURRENT_TIMESTAMP WHERE id=?",
      [bio, profile_pic_url, userId]
    );
    const [rows] = await pool.query(
      "SELECT id, username, code, bio, profile_pic_url FROM users WHERE id=?", [userId]);
    res.json({ ok:true, user: rows[0] });
  } catch (err) {
    console.error("UPDATE PROFILE ERROR:", err);
    res.status(500).json({ ok:false, msg:"Errore server" });
  }
};

// ---------- CHANGE PASSWORD ----------
exports.changePassword = async (req, res) => {
  try {
    const userId = req.user.id;
    const { oldPassword, newPassword } = req.body;
    if (!oldPassword || !newPassword) {
      await delay(AUTH_DELAY_MS);
      return res.status(400).json({ ok:false, msg:"Password richiesta" });
    }
    const [rows] = await pool.query(
      "SELECT id, password_hash, failed_attempts, blocked_until FROM users WHERE id=?", [userId] );
    if (!rows.length) {
      await delay(AUTH_DELAY_MS);
      return res.status(404).json({ ok:false, msg:"Utente non trovato" });
    }
    const user = rows[0];
    if (isBlocked(user)) {
      await delay(AUTH_DELAY_MS);
      return res.status(403).json({ ok:false, msg:"Account temporaneamente bloccato" });
    }
    const match = await bcrypt.compare(oldPassword, user.password_hash);
    if (!match) {
      await registerFailedLogin(user);
      await delay(AUTH_DELAY_MS);
      return res.status(401).json({ ok:false, msg:"Password attuale errata" });
    }
    if (newPassword.length < 8) return res.status(400).json({ ok:false, msg:"Password troppo corta" });
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await pool.query("UPDATE users SET password_hash=?, updated_at=CURRENT_TIMESTAMP WHERE id=?", [hashedPassword, userId]);
    await resetLoginFailures(userId);
    res.json({ ok:true, msg:"Password aggiornata correttamente" });
  } catch (err) {
    console.error("CHANGE PASSWORD ERROR:", err);
    await delay(AUTH_DELAY_MS);
    res.status(500).json({ ok:false, msg:"Errore server" });
  }
};