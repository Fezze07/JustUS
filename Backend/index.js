const { env, startRetentionJobs } = require("./all_imports");
const { createApp } = require("./app");

const app = createApp();

if (require.main === module) {
  app.listen(env.port, "0.0.0.0", () => {
    console.log(`Server ${env.nodeEnv} attivo su ${env.port}`);
    startRetentionJobs();
  });
}

module.exports = {
  app,
};