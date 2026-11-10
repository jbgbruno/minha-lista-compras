const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const htmlPath = path.resolve(__dirname, "..", "index.html");
const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (pathname !== "/" && pathname !== "/index.html") {
        response.writeHead(404).end("Not found");
        return;
    }
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    fs.createReadStream(htmlPath).pipe(response);
});

server.listen(4173, "127.0.0.1");
