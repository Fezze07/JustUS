const http = require("http");

const port = Number.parseInt(process.env.PORT ?? "11434", 10);
const defaultPayload = process.env.MOCK_AI_RESPONSE;

function collectBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString();
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  // Readiness probe. Exists so scripts/test-all.sh can poll for the port
  // instead of sleeping a fixed number of seconds and racing the container.
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  if (req.method !== "POST" || req.url !== "/api/generate") {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not_found" }));
    return;
  }

  await collectBody(req);

  res.writeHead(200, {
    "Content-Type": "application/x-ndjson",
    Connection: "keep-alive",
    "Transfer-Encoding": "chunked",
  });

  res.write(`${JSON.stringify({ response: defaultPayload })}\n`);
  res.end();
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Mock AI server listening on ${port}`);
});
