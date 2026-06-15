function success(res, data = {}, status = 200) {
  return res.status(status).json({ success: true, ...data });
}

function fail(res, error, status = 400) {
  return res.status(status).json(error);
}

function notFound(res, message = "Resource not found") {
  return res.status(404).json({ success: false, message });
}

module.exports = { success, fail, notFound };
