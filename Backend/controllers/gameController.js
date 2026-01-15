const pool = require("../config/db");
const { tipiDomanda, generateAIQuestion } = require("../config/aiConfig");
const { getPartnerId } = require("../utils/partnershipUtils");

// ---------- GENERA DOMANDA ----------
async function generateQuestion(req, res) {
  try {
    const userId = req.user?.id;
    if (!userId) return res.status(400).json({ success: false, error: "Utente non valido" });
    const partnerId = await getPartnerId(userId);
    if (!partnerId) return res.status(400).json({ success: false, error: "Nessun partner collegato" });
    const [[userRow]] = await pool.query("SELECT username FROM users WHERE id=?", [userId]);
    const [[partnerRow]] = await pool.query("SELECT username FROM users WHERE id=?", [partnerId]);
    if (!partnerRow) return res.status(404).json({ success: false, error: "Partner non trovato" });
    const userUsername = userRow.username;
    const partnerUsername = partnerRow.username;
    const [pending] = await pool.query(`
    SELECT q.id, q.text, q.user_id
    FROM game_questions q
    WHERE ((q.user_id=? AND q.partner_id=?) OR (q.user_id=? AND q.partner_id=?))
      AND (SELECT COUNT(*) FROM game_answers a WHERE a.game_id = q.id) < 2
    ORDER BY q.created_at DESC
    LIMIT 1
  `, [userId, partnerId, partnerId, userId]);
    if (pending.length > 0) {
      const q = pending[0];
      const [mine] = await pool.query(`SELECT id FROM game_answers WHERE game_id=? AND user_id=?`, [q.id, userId]);
      const isCreatedByCurrentUser = q.user_id === userId;
      const optionA = isCreatedByCurrentUser ? userUsername : partnerUsername;
      const optionB = isCreatedByCurrentUser ? partnerUsername : userUsername;
      return res.json({
        success: true,
        id: q.id,
        question: q.text,
        optionA: optionA,
        optionB: optionB,
        status: mine.length > 0 ? "waiting" : "pending",
        message: mine.length > 0 ? "Aspetta che l'altro risponda" : undefined
      });
    }
    const tipo = tipiDomanda[Math.floor(Math.random() * tipiDomanda.length)];
    console.log("[GAME] Generazione domanda per userId:", userId, "partnerId:", partnerId);
    const ai = await generateAIQuestion(tipo);
    console.log("[GAME] Risultato AI:", ai);
    const questionText = ai.question || "Domanda non disponibile";
    const [result] = await pool.query(`
      INSERT INTO game_questions (user_id, partner_id, text)
      VALUES (?, ?, ?)
    `, [userId, partnerId, questionText]);
    return res.json({
      success: true,
      status: "new",
      id: result.insertId,
      question: questionText,
      optionA: userUsername,
      optionB: partnerUsername
    });
  } catch (e) {
    console.error("Errore generateQuestion:", e);
    return res.status(500).json({ success: false, error: e.message });
  }
}

// ---------- SALVA RISPOSTA ----------
async function saveAnswer(req, res) {
  const { questionId, votedFor } = req.body;
  if (!questionId || !["A", "B"].includes(votedFor)) {
    return res.status(400).json({ success: false, error: "Dati non validi" });
  }
  try {
    const responderId = req.user.id;
    const [rows] = await pool.query(
      "SELECT user_id, partner_id FROM game_questions WHERE id=?", [questionId] );
    if (!rows.length) {
      return res.status(404).json({ success: false, error: "Domanda non trovata" });
    }
    const { user_id: creatorId, partner_id: receiverId } = rows[0];
    if (![creatorId, receiverId].includes(responderId)) {
      return res.status(403).json({ success: false, error: "Non autorizzato" });
    }
    const partnerId = responderId === creatorId ? receiverId : creatorId;
    if (!partnerId) {
      return res.status(500).json({ success: false, error: "Partner non valido" });
    }
    const votedUserId = votedFor === "A" ? responderId : partnerId;
    await pool.query(`
      INSERT INTO game_answers (game_id, user_id, partner_id, selected_option)
      VALUES (?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        selected_option = VALUES(selected_option)
    `, [questionId, responderId, partnerId, votedUserId]);
    res.json({ success: true });
  } catch (e) {
    console.error("Errore saveAnswer:", e);
    res.status(500).json({ success: false, error: "Errore server" });
  }
}

// ---------- STATISTICHE GLOBALI ----------
async function getStats(req, res) {
  try {
    const [rows] = await pool.query(`
      SELECT COUNT(*) AS totalMatches
      FROM (
        SELECT game_id
        FROM game_answers
        GROUP BY game_id
        HAVING COUNT(*) = 2
          AND COUNT(DISTINCT selected_option) = 1 
      ) AS sub
    `);
    res.json({ success: true, totalMatches: rows[0].totalMatches });
  } catch (e) {
    console.error("Errore getStats:", e);
    res.status(500).json({ success: false, error: e.message });
  }
}

module.exports = { generateQuestion, saveAnswer, getStats };