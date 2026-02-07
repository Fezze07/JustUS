require('dotenv').config({ path: __dirname + '/config/.env' });
const express = require("express");
const path = require("path");

const app = express();
const pingRoutes = require("./routes/ping");
const missyouRoutes = require("./routes/missyou");
const authRoutes = require("./routes/auth");
const moodRoutes = require("./routes/mood");
const bucketRoutes = require("./routes/bucket");
const gameRoutes = require("./routes/game");
const driveRoutes = require("./routes/drive");
const uploadRoutes = require("./routes/upload");
const notifyRoutes = require("./routes/notify");
const versionRoutes = require('./routes/version');
const deployRoutes = require('./routes/deploy');
const partnershipRoutes = require('./routes/partnerships');
const profileRoutes = require('./routes/profile');

// Token per autenticazione
const authenticateToken = require("./middleware/authMiddleware");

app.set('trust proxy', true);
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use("/versions", express.static(path.join(__dirname, 'versions')));

// Rotte senza autenticazione
app.use("/", pingRoutes);
app.use("/auth", authRoutes);
app.use('/app-version', versionRoutes);
app.use('/deploy', deployRoutes);

// Rotte con autenticazione
app.use("/missyou", authenticateToken, missyouRoutes);
app.use("/mood", authenticateToken, moodRoutes);
app.use("/bucket", authenticateToken, bucketRoutes);
app.use("/game", authenticateToken, gameRoutes);
app.use("/drive", authenticateToken, driveRoutes);
app.use("/upload", authenticateToken, uploadRoutes);
app.use("/notify", authenticateToken, notifyRoutes);
app.use("/partnerships", authenticateToken, partnershipRoutes);
app.use("/profile", authenticateToken, profileRoutes);

// Backend/index.js
const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', () => console.log(`Server debug attivo su ${PORT}`));
