const {
  asyncHandlerWithCallback,
  API_V1_PATHS,
  createAiQuestion,
} = require("../../all_imports");
const { onAiQuestionFailure } = require("./aiQuestion.service");

const generateQuestionController = asyncHandlerWithCallback(async (req, res) => {
  const payload = await createAiQuestion({
    user: req.user,
    type: req.body.type,
    ipAddress: req.ip,
    endpointPath: API_V1_PATHS.aiQuestion,
  });

  res.json(payload);
}, () => onAiQuestionFailure("ai-question"));

module.exports = {
  generateQuestionController,
};
