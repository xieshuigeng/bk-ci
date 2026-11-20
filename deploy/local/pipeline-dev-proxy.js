const http = require('http');
const net = require('net');

const PORT = 8088;
const TARGETS = {
  pipeline: { host: '127.0.0.1', port: 8006 },
  default: { host: '127.0.0.1', port: 8080 },
};

function pick(url) {
  return url && url.startsWith('/pipeline/') ? TARGETS.pipeline : TARGETS.default;
}

const server = http.createServer((req, res) => {
  const target = pick(req.url);
  const proxy = http.request({
    host: target.host,
    port: target.port,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: `${target.host}:${target.port}` },
  }, (upstream) => {
    res.writeHead(upstream.statusCode || 502, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on('error', () => {
    res.writeHead(502);
    res.end('bad gateway');
  });
  req.pipe(proxy);
});

server.on('upgrade', (req, socket, head) => {
  const target = pick(req.url);
  const upstream = net.connect(target.port, target.host, () => {
    upstream.write(
      `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
      Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') +
      '\r\n\r\n'
    );
    if (head.length) upstream.write(head);
    socket.pipe(upstream);
    upstream.pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`pipeline dev proxy listening on :${PORT}`);
});
