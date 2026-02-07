const db = require('../config/db');
const fs = require('fs');
const path = require('path');
const { getPartnerId } = require("../utils/partnershipUtils");

// GET /drive
const getAllItems = async (req, res) => {
  try {
    const [items] = await db.query(
      `SELECT d.*,
      u.username AS author_name,
        IF(f.id IS NULL, 0, 1) AS is_favorite
      FROM drive_items d
      JOIN users u ON d.user_id = u.id
      LEFT JOIN favorites f 
        ON f.drive_item_id = d.id 
        AND f.user_id = ?
      WHERE d.user_id = ? OR d.partner_id = ?
      ORDER BY d.created_at DESC`,
      [req.user.id, req.user.id, req.user.id] );
    res.json({ success: true, items });
  } catch (err) { 
    res.status(500).json({ success: false, error: err.message }); 
  }
};

// POST /drive
const createItem = async (req, res) => {
  try {
    const { type, content, metadata } = req.body;
    if (!type || !content) return res.status(400).json({ success:false, error:"Missing data" });
    const partner_id = await getPartnerId(req.user.id);
    const [result] = await db.query(
      `INSERT INTO drive_items (user_id, partner_id, type, content, metadata) VALUES (?, ?, ?, ?, ?)`,
      [req.user.id, partner_id, type, content, metadata ? JSON.stringify(metadata) : null]
    );
    const [item] = await db.query('SELECT * FROM drive_items WHERE id = ?', [result.insertId]);
    res.status(201).json({ success: true, item: item[0] });
  } catch (err) { 
    console.error(err);
    res.status(500).json({ success: false, error: err.message }); 
  }
};

// GET /drive/:id
const getItemById = async (req, res) => {
  try {
    const [item] = await db.query(
      `SELECT d.*, u.username AS author_name
       FROM drive_items d
       JOIN users u ON d.user_id = u.id
       WHERE d.id = ? AND (d.user_id = ? OR d.partner_id = ?)`,
      [req.params.id, req.user.id, req.user.id]
    );
    if (!item.length) return res.status(404).json({ success: false, error: 'Item non trovato' });
    res.json({ success: true, item: item[0] });
  } catch (err) { 
    res.status(500).json({ success: false, error: err.message }); 
  }
};

// DELETE /drive/:id
const deleteItem = async (req, res) => {
  try {
    const [rows] = await db.query(
      'SELECT * FROM drive_items WHERE id = ? AND (user_id = ? OR partner_id = ?)',
      [req.params.id, req.user.id, req.user.id] );
    if (!rows.length) return res.status(404).json({ success: false, message: 'Item non trovato' });
    const item = rows[0];
    if (['image', 'video', 'audio'].includes(item.type) && item.content) {
      const filePath = path.join(__dirname, '..', item.content);
      fs.unlink(filePath, err => err && console.warn('Impossibile eliminare file:', filePath, err.message));
    }
    await db.query('DELETE FROM drive_items WHERE id = ?', [req.params.id]);
    res.json({ success: true, message: 'Item eliminato' });
  } catch (err) { 
    res.status(500).json({ success: false, error: err.message }); 
  }
};

// GET /drive/changes?since=...
const getDriveChanges = async (req, res) => {
  try {
    const since = req.query.since || '1970-01-01T00:00:00Z';
    const [updated] = await db.query(
      `SELECT * FROM drive_items 
       WHERE (user_id = ? OR partner_id = ?) AND updated_at > ?`,
      [req.user.id, req.user.id, since]
    );
    const [deleted] = await db.query(
      `SELECT id FROM drive_items 
       WHERE (user_id = ? OR partner_id = ?) AND updated_at > ? AND content IS NULL`,
      [req.user.id, req.user.id, since]
    );
    const changes = [
      ...updated.map(item => ({ id: item.id, action: 'update', item })),
      ...deleted.map(d => ({ id: d.id, action: 'delete', item: null }))
    ];
    res.json({ success: true, changes, lastSync: new Date().toISOString() });
  } catch (err) { 
    res.status(500).json({ success: false, error: err.message }); 
  }
};

// POST /drive/:id/reaction
const addReaction = async (req, res) => {
  const { id } = req.params;
  const { emoji } = req.body;
  const user_id = req.user.id;
  try {
    await db.query(
      'INSERT INTO drive_item_reactions (item_id, user_id, emoji) VALUES (?,?,?)', [id, user_id, emoji]);
    const [counts] = await db.query(
      'SELECT emoji, COUNT(*) as total FROM drive_item_reactions WHERE item_id=? GROUP BY emoji',[id]);
    res.json({ success: true, counts });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

// GET /drive/:id/reactions
const getReactionsForItem = async (req, res) => {
  const { id } = req.params;
  try {
    const [reactions] = await db.query(
      'SELECT user_id, emoji FROM drive_item_reactions WHERE item_id=?', [id]);
    res.json({ success: true, reactions });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

const addFavorite = async (req, res) => {
  try {
    const userId = req.user.id;
    const itemId = req.params.id;
    await db.query(
      `INSERT IGNORE INTO favorites (user_id, drive_item_id) VALUES (?, ?)`, [userId, itemId] );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

const removeFavorite = async (req, res) => {
  try {
    const userId = req.user.id;
    const itemId = req.params.id;
    await db.query(
      `DELETE FROM favorites WHERE user_id = ? AND drive_item_id = ?`, [userId, itemId] );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

module.exports = { getAllItems, createItem, getItemById, 
  deleteItem, getDriveChanges, addReaction, 
  getReactionsForItem, addFavorite, removeFavorite};