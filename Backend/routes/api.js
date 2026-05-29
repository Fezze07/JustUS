const express = require("express");
const v1Routes = require("./v1");

function createApiRouter() {
  const router = express.Router();

  router.use("/v1", v1Routes);

  return router;
}

module.exports = createApiRouter;
