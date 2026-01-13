// routes/deploy.js
require('dotenv').config({ path: __dirname + '/../config/.env' });
const express = require('express');
const { exec } = require('child_process');
const crypto = require('crypto');

const router = express.Router();

// Funzione per calcolare HMAC SHA256
function verifyGitHubSignature(secret, payload, signature) {
    const hmac = crypto.createHmac('sha256', secret);
    const digest = 'sha256=' + hmac.update(payload).digest('hex');
    return crypto.timingSafeEqual(Buffer.from(digest), Buffer.from(signature));
}

router.post('/', express.json({ type: '*/*' }), (req, res) => {
    const signature = req.headers['x-hub-signature-256'];
    if (!signature) {
        return res.status(400).send('No signature found');
    }
    const payload = JSON.stringify(req.body);
    if (!verifyGitHubSignature(process.env.DEPLOY_SECRET, payload, signature)) {
        return res.status(403).send('Forbidden: signature mismatch');
    }
    console.log('Webhook GitHub verificato ✅, deploy in corso...');
    exec('~/scripts/deploy-justUs.sh', (err, stdout, stderr) => {
        if (err) {
            console.error('Errore deploy:', err);
            return res.status(500).send('Errore deploy');
        }
        console.log(stdout);
        console.error(stderr);
        res.send('Deploy completato!');
    });
});

module.exports = router;