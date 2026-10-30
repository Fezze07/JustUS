function success(res, data = {}, status = 200) {
  return res.status(status).json({ success: true, ...data });
}

function fail(res, error, status = 400) {
  return res.status(status).json(error);
}

module.exports = { success, fail };
