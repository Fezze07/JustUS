const pool = require("../config/db");

async function getPartnerId(userId) {
    const [rows] = await pool.query(
        ` SELECT 
            CASE WHEN user_id = ? THEN partner_id ELSE user_id END AS partner_id
          FROM partnerships
          WHERE (user_id = ? OR partner_id = ?)
            AND status = 'accepted'
          LIMIT 1`,
        [userId, userId, userId]
    );
    return rows.length ? rows[0].partner_id : null;
}

module.exports = { getPartnerId };