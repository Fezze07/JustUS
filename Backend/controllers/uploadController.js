const db = require("../config/db");

// Upload foto profilo
exports.uploadProfile = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, message: 'Nessun file caricato' });
    const profileUrl = `/uploads/profile/${req.file.filename}`;
    await db.query(
      'UPDATE users SET profile_pic_url = ?, updated_at = NOW() WHERE id = ?', [profileUrl, req.user.id]);
    res.status(201).json({
      success: true,
      url: profileUrl,
      size: req.file.size,
      mime: req.file.mimetype,
      uploadedBy: req.user.id
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, message: 'Errore server' });
  }
};

// Upload diary/drive
exports.uploadDrive = (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, message: 'Nessun file caricato' });
  const basePath = `/uploads/couples/couple_${req.uploadContext.coupleId}/drive/${req.file.filename}`;
  res.status(201).json({
    success: true,
    url: basePath,
    size: req.file.size,
    mime: req.file.mimetype,
    uploadedBy: req.user.id
  });
};