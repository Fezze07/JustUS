const express = require("express");
const { asyncHandler } = require("../all_imports");
const { buildCallbackPage } = require("../templates/callbackPage");

const router = express.Router();

const inviteCallbackController = asyncHandler(async (req, res) => {
  res.status(200).send(
    buildCallbackPage({
      title: "Invito Accettato!",
      body: "L'invito è stato verificato con successo. Puoi chiudere questa pagina e tornare all'app JustUs per iniziare.",
      pageTitle: "Invito Ricevuto - JustUs",
    })
  );
});

const inviteLandingController = asyncHandler(async (req, res) => {
  // Target of the partner invite email. Informational only: no token, no Auth
  // call, nothing that could confirm or sign in an account.
  res.status(200).send(
    buildCallbackPage({
      title: "Benvenuto su JustUS!",
      body: "Il tuo partner ti ha invitato. Scarica l'app sul telefono, aprila e crea il tuo account con questa mail.",
      icon: "💜",
      pageTitle: "Invito a JustUS",
    })
  );
});

const webCallbackController = asyncHandler(async (req, res) => {
  // This route is hit when the deep link fails (e.g. opened on PC)
  // Serve a friendly success page instructing the user to return to the app.
  res.status(200).send(
    buildCallbackPage({
      title: "Email Confermata!",
      body: "La tua email è stata verificata con successo. Puoi chiudere questa pagina e tornare all'app JustUs per continuare.",
      pageTitle: "Autenticazione Riuscita - JustUs",
    })
  );
});

router.get("/callback", webCallbackController);
router.get("/invite", inviteLandingController);
router.get("/invite-callback", inviteCallbackController);

module.exports = router;
