require('dotenv').config({ path: __dirname + '/../config/.env' });
const express = require('express');
const { exec } = require('child_process');
const crypto = require('crypto');

const router = express.Router();

function verifyGitHubSignature(secret, payload, signature) {
  const hmac = crypto.createHmac('sha256', secret);
  const digest = 'sha256=' + hmac.update(payload).digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(digest),
    Buffer.from(signature)
  );
}

router.post('/', express.json({ type: '*/*' }), (req, res) => {
  const signature = req.headers['x-hub-signature-256'];
  if (!signature) return res.status(400).send('No signature');
  const payload = JSON.stringify(req.body);
  if (!verifyGitHubSignature(process.env.DEPLOY_SECRET, payload, signature)) {
    return res.status(403).send('Forbidden');
  }
  const branch = req.body.ref.replace('refs/heads/', '');
  console.log(`🚀 Webhook GitHub OK → branch: ${branch}`);
  res.status(200).send('OK');
  exec(
    `/home/federico/justUs/scripts/deploy-justUs.sh ${branch}`,
    (err, stdout, stderr) => {
      if (err) {
        console.error('❌ Errore deploy:', err);
        return;
      }
      if (stdout) console.log(stdout);
      if (stderr) console.error(stderr);
    }
  );
});

module.exports = router;