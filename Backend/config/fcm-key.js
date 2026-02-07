const admin = require("firebase-admin");
const serviceAccount = require("./fcm-key.json");

// Inizializzazione Firebase Admin (evita doppie inizializzazioni)
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}
async function sendNotification(deviceToken, title, body) {
    const message = {
        token: deviceToken,
        notification: {
            title,
            body,
        },
    };
    try {
        await admin.messaging().send(message);
        console.log("Notifica inviata!");
    } catch (error) {
        console.error("Errore invio notifica:", error);
    }
}

module.exports = { sendNotification };