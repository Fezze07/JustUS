const admin = require("firebase-admin");

let serviceAccount;
try { serviceAccount = require("../secrets/fcm-key.json"); } catch { /* file missing in test */ }
if (serviceAccount && admin.credential?.cert && !admin.apps?.length) {
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