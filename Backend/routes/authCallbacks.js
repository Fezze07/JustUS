const express = require("express");
const { asyncHandler, getLatestAppVersion, logAppError } = require("../all_imports");
const { buildCallbackPage } = require("../templates/callbackPage");

const router = express.Router();

const inviteCallbackController = asyncHandler(async (req, res) => {
  res.status(200).send(
    buildCallbackPage({
      title: "Invito Accettato!",
      body: "L'invito è stato verificato con successo. Puoi chiudere questa pagina e tornare all'app JustUS per iniziare.",
      pageTitle: "Invito Ricevuto - JustUS",
    })
  );
});

const inviteLandingController = asyncHandler(async (req, res) => {
  // Target of the partner invite email. Informational only: no token, no Auth
  // call, nothing that could confirm or sign in an account.
  let downloadUrl = null;
  try {
    const versionInfo = await getLatestAppVersion();
    if (versionInfo && versionInfo.apk_url) {
      downloadUrl = versionInfo.apk_url;
    }
  } catch (err) {
    await logAppError({
      request_id: req.requestId ?? null,
      code: err.code || "SYS-FAIL-001",
      message: `Failed to load app version metadata for invite landing: ${err.message}`,
      user_id: req.user?.profileId ?? null,
      method: req.method,
      path: req.originalUrl,
      severity: "LOW",
      ip_address: req.ip ?? null,
      stack: err.stack,
    });
  }

  res.status(200).send(
    buildCallbackPage({
      title: "Benvenuto su JustUS!",
      body: "Il tuo partner ti ha invitato. Scarica l'app sul telefono, aprila e crea il tuo account con questa mail.",
      icon: "💜",
      pageTitle: "Invito a JustUS",
      ctaUrl: downloadUrl || "https://github.com/Fezze07/JustUS/releases/",
      ctaText: "Scarica l'App",
    })
  );
});

const webCallbackController = asyncHandler(async (req, res) => {
  // This route is hit when the deep link fails (e.g. opened on PC)
  // Serve a friendly success page instructing the user to return to the app.
  res.status(200).send(
    buildCallbackPage({
      title: "Email Confermata!",
      body: "La tua email è stata verificata con successo. Puoi chiudere questa pagina e tornare all'app JustUS per continuare.",
      pageTitle: "Autenticazione Riuscita - JustUS",
    })
  );
});

router.get("/callback", webCallbackController);
router.get("/invite", inviteLandingController);
router.get("/invite-callback", inviteCallbackController);

module.exports = router;
