const pool = require("../config/db");
const bcrypt = require("bcrypt");
require('dotenv').config({ path: __dirname + '/config/.env' });
const ACCESS_TOKEN_EXPIRES = process.env.ACCESS_TOKEN_EXPIRES?.trim();
const REFRESH_TOKEN_EXPIRES = process.env.REFRESH_TOKEN_EXPIRES?.trim();
const jwt = require("jsonwebtoken");
const SECRET = process.env.JWT_SECRET;
const AUTH_DELAY_MS = 600;
const { delay, isBlocked, registerFailedLogin, resetLoginFailures, logFailedAttempt } = require('../utils/authUtils');

// ---------- REGISTER ----------
async function registerUser(req, res) {
  try {
    const { username, password, email, deviceToken } = req.body;
    if (!username || !password) {
      await logFailedAttempt({ ip: req.ip, reason: "REGISTER_MISSING_DATA" });
      return res.status(400).json({ ok: false, msg: "Dati mancanti" });
    }
    let code, rows;
    do {
      code = Math.floor(100000 + Math.random() * 900000).toString();
      [rows] = await pool.query("SELECT id FROM users WHERE username=? AND code=?", [username, code]);
    } while (rows.length);
    const hash = await bcrypt.hash(password, 10);
    const [r] = await pool.query(
      "INSERT INTO users (username,code,password_hash,email,deviceToken) VALUES (?,?,?,?,?)",
      [username, code, hash, email || null, deviceToken || null]
    );
    res.json({ ok: true, user: { id: r.insertId, username, code } });
  } catch (e) {
    console.error("REGISTER", e);
    res.status(500).json({ ok: false, msg: "Register failed" });
  }
}

// ---------- LOGIN ----------
async function loginUser(req, res) {
  try {
    const { usernameWithCode, password, deviceToken } = req.body;
    if (!usernameWithCode || !password || !deviceToken) {
      await delay(AUTH_DELAY_MS);
      await logFailedAttempt({ userId: null, ip: req.ip, reason: "LOGIN_MISSING_DATA" });
      return res.status(400).json({ ok: false, msg: "Il codice inviato non è valido" });
    }
    if (!usernameWithCode.includes("#")) {
      await delay(AUTH_DELAY_MS);
      await logFailedAttempt({ userId: null, ip: req.ip, reason: "LOGIN_BAD_FORMAT" });
      return res.status(400).json({ ok: false, msg: "Credenziali non inviate correttamente" });
    }
    const [username, code] = usernameWithCode.split("#");
    const [rows] = await pool.query("SELECT * FROM users WHERE username=? AND code=?", [username, code]);
    if (!rows.length) {
      await delay(AUTH_DELAY_MS);
      await logFailedAttempt({ userId: null, code, ip: req.ip, reason: "LOGIN_USER_NOT_FOUND" });
      return res.status(401).json({ ok: false, msg: "Il nome utente non è stato trovato" });
    }
    const user = rows[0];
    if (isBlocked(user)) {
      await logFailedAttempt({ userId: user.id, code, ip: req.ip, reason: "ACCOUNT_BLOCKED" });
      return res.status(403).json({ ok: false, msg: "Account temporaneamente bloccato. Riprova più tardi." });
    }
    const passOk = await bcrypt.compare(password, user.password_hash);
    if (!passOk) {
      await delay(AUTH_DELAY_MS);
      await registerFailedLogin(user);
      await logFailedAttempt({ userId: user.id, code, ip: req.ip, reason: "LOGIN_WRONG_PASSWORD" });
      return res.status(401).json({ ok: false, msg: "Password errata" });
    }
    if (!SECRET) {
      await delay(AUTH_DELAY_MS);
      return res.status(500).json({ ok: false, msg: "Errore server" });
    }
    await pool.query("UPDATE users SET deviceToken=? WHERE id=?", [deviceToken, user.id]);
    const accessToken = jwt.sign({ id: user.id }, SECRET, { expiresIn: ACCESS_TOKEN_EXPIRES });
    const refreshToken = jwt.sign({ id: user.id }, SECRET, { expiresIn: REFRESH_TOKEN_EXPIRES });
    await delay(AUTH_DELAY_MS);
    await resetLoginFailures(user.id);
    res.json({ ok: true, accessToken, refreshToken, user: { id: user.id, username, code } });
  } catch (e) {
    console.error("LOGIN ERRORE:", e);
    await delay(AUTH_DELAY_MS);
    res.status(500).json({ ok: false, msg: "Errore server" });
  }
}

// ---------- REQUEST USER CODES ----------
async function requestUserCodes(req, res) {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      await delay(AUTH_DELAY_MS);
      await logFailedAttempt({ userId: null, ip: req.ip, reason: "REQUEST_CODE_MISSING_DATA" });
      return res.status(400).json({ ok: false, msg: "Credenziali errate" });
    }
    const [rows] = await pool.query(
      "SELECT id, code, password_hash, failed_attempts, blocked_until FROM users WHERE username=?", [username]);
    if (!rows.length) {
      await delay(AUTH_DELAY_MS);
      await logFailedAttempt({ userId: null, ip: req.ip, reason: "REQUEST_CODE_USER_NOT_FOUND" });
      return res.status(401).json({ ok: false, msg: "Credenziali errate" });
    }
    if (rows.some(user => isBlocked(user))) {
      await logFailedAttempt({ userId: rows.find(u => isBlocked(u)).id, ip: req.ip, reason: "ACCOUNT_BLOCKED" });
      return res.status(403).json({ ok: false, msg: "Account temporaneamente bloccato. Riprova più tardi." });
    }
    let validUser = null;
    for (const user of rows) {
      if (await bcrypt.compare(password, user.password_hash)) {
        validUser = user;
        break;
      }
    }
    if (!validUser) {
      await delay(AUTH_DELAY_MS);
      for (const user of rows) {
        await registerFailedLogin(user);
      }
      await logFailedAttempt({ userId: null, ip: req.ip, reason: "REQUEST_CODE_WRONG_PASSWORD" });
      return res.status(401).json({ ok: false, msg: "Credenziali errate" });
    }
    for (const user of rows) {
      await resetLoginFailures(user.id);
    }
    const codes = rows.map(u => u.code);
    await delay(AUTH_DELAY_MS);
    return res.json({ ok: true, codes });
  } catch (e) {
    console.error("REQUEST CODES ERRORE:", e);
    await delay(AUTH_DELAY_MS);
    res.status(500).json({ ok: false, msg: "Errore server" });
  }
}

// ---------- UPDATE DEVICE TOKEN ----------
async function updateDeviceToken(req, res) {
  try {
    const { usernameWithCode, deviceToken } = req.body;
    if (!usernameWithCode || !deviceToken)
      return res.status(400).json({ ok: false, msg: "Dati mancanti" });
    if (!usernameWithCode.includes("#"))
      return res.status(400).json({ ok: false, msg: "Formato errato" });
    const [username, code] = usernameWithCode.split("#");
    const [rows] = await pool.query(
      "SELECT id FROM users WHERE username=? AND code=?", [username, code]);
    if (!rows.length) return res.status(404).json({ ok: false, msg: "Utente non trovato" });
    await pool.query(
      "UPDATE users SET deviceToken=? WHERE id=?",
      [deviceToken, rows[0].id]
    );
    res.json({ ok: true });
  } catch (err) {
    console.error("UPDATE TOKEN ERROR:", err);
    res.status(500).json({ ok: false, msg: "Errore interno" });
  }
}

// ---------- REFRESH TOKEN ----------
async function refreshToken(req, res) {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return res.status(400).json({ ok: false, msg: "Refresh token mancante" });
    }
    if (!SECRET) {
      return res.status(500).json({ ok: false, msg: "Errore server" });
    }
    let payload;
    try {
      payload = jwt.verify(refreshToken, SECRET);
    } catch (err) {
      return res.status(401).json({ ok: false, msg: "Refresh token non valido o scaduto" });
    }
    const newAccessToken = jwt.sign({ id: payload.id }, SECRET, { expiresIn: ACCESS_TOKEN_EXPIRES });
    const newRefreshToken = jwt.sign({ id: payload.id }, SECRET, { expiresIn: REFRESH_TOKEN_EXPIRES });
    res.json({ success: true, accessToken: newAccessToken, refreshToken: newRefreshToken });
  } catch (err) {
    console.error("REFRESH TOKEN ERROR:", err);
    res.status(500).json({ ok: false, msg: "Errore server" });
  }
}

module.exports = { registerUser, loginUser, requestUserCodes, updateDeviceToken, refreshToken };