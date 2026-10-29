const { AppError } = require("../../all_imports");
const { acceptPartnershipCancellation } = require("./partnership.service");

async function acceptCancellation(req, res, next) {
  try {
    const { partnershipId } = req.body;
    const actorId = req.user?.profileId;
    if (!actorId) throw new AppError({ errorKey: "AUTH_FAIL_001" });
    const result = await acceptPartnershipCancellation({ partnershipId, actorId });
    res.json(result);
  } catch (err) {
    next(err);
  }
}

module.exports = { acceptCancellation };
