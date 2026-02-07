const pool = require("../config/db");

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function isBlocked(user) {
  return user.blocked_until && new Date(user.blocked_until) > new Date();
}

async function registerFailedLogin(user) {
  const attempts = user.failed_attempts + 1;
  if (attempts >= 5) {
    const blockUntil = new Date(Date.now() + 30*60*1000); // 30 min
    await pool.query(
      "UPDATE users SET failed_attempts=?, blocked_until=? WHERE id=?",
      [attempts, blockUntil, user.id]
    );
  } else {
    await pool.query(
      "UPDATE users SET failed_attempts=? WHERE id=?",
      [attempts, user.id]
    );
  }
}

async function resetLoginFailures(userId) {
  await pool.query(
    "UPDATE users SET failed_attempts=0, blocked_until=NULL WHERE id=?",
    [userId]
  );
}

async function logFailedAttempt({ userId = null, code = null, ip, reason }) {
  try {
    await pool.query(
      `INSERT INTO auth_failed_attempts 
       (user_id, code, ip_address, reason)
       VALUES (?, ?, ?, ?)`,
      [userId, code, ip, reason]
    );
  } catch (e) {
    console.error("LOG FAILED ATTEMPT ERROR:", e);
  }
}

module.exports = { delay, isBlocked, registerFailedLogin, resetLoginFailures, logFailedAttempt };