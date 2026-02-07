const express = require('express');
const router = express.Router();
const bucketController = require('../controllers/bucketController');
const authenticateToken = require('../middleware/authMiddleware');

router.get('/', authenticateToken, bucketController.getAll);
router.post('/', authenticateToken, bucketController.addItem);
router.patch('/:id', authenticateToken, bucketController.toggleDone);
router.delete('/:id', authenticateToken, bucketController.deleteItem);

module.exports = router;