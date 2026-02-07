const express = require('express');
const router = express.Router();
const driveController = require('../controllers/driveController');
const authenticateToken = require('../middleware/authMiddleware');

router.get('/changes', authenticateToken, driveController.getDriveChanges);
router.get('/', authenticateToken, driveController.getAllItems);
router.post('/', authenticateToken, driveController.createItem);
router.post('/:id/favorite', authenticateToken, driveController.addFavorite);
router.delete('/:id/favorite', authenticateToken, driveController.removeFavorite);
router.post('/:id/reaction', authenticateToken, driveController.addReaction);
router.get('/:id/reactions', authenticateToken, driveController.getReactionsForItem);
router.get('/:id', authenticateToken, driveController.getItemById);
router.delete('/:id', authenticateToken, driveController.deleteItem);

module.exports = router;