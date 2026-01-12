const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/authMiddleware');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const uploadController = require('../controllers/uploadController');
const { getPartnerId } = require('../utils/partnershipUtils');

// ----- FOTO PROFILO -----
const profileStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const folder = path.join(__dirname, '../uploads/profile');
    fs.mkdirSync(folder, { recursive: true });
    cb(null, folder);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `user_${req.user.id}${ext}`);
  }
});

// ----- FILE DIARY (DRIVE) -----
const driveStorage = multer.diskStorage({
  destination: async (req, file, cb) => {
    try {
      const userId = req.user.id;
      const partnerId = await getPartnerId(userId);
      if (!partnerId) return cb(new Error('Partner non trovato'));

      const coupleId = [userId, partnerId].sort().join('_');
      const folder = path.join(__dirname, `../uploads/couples/couple_${coupleId}/drive`);
      fs.mkdirSync(folder, { recursive: true });
      req.uploadContext = { coupleId, folder };
      cb(null, folder);
    } catch (err) {
      cb(err);
    }
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const unique = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, `${unique}${ext}`);
  }
});

const profileUpload = multer({ storage: profileStorage }).single('file');
const driveUpload = multer({ storage: driveStorage }).single('file');
router.post('/diary', authenticateToken, driveUpload, uploadController.uploadDrive);
router.post('/profile', authenticateToken, profileUpload, uploadController.uploadProfile);

module.exports = router;