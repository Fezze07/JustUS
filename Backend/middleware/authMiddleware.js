const jwt = require('jsonwebtoken');
const SECRET = process.env.JWT_SECRET;

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ success: false, error: "Token mancante" });
  try {
    const user = jwt.verify(token, SECRET);
    req.user = user;
    next();
  } catch (err) {
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Token scaduto, rifai il login" });
    }
    return res.status(401).json({ error: "Token non valido" });
  }
}

module.exports = authenticateToken;