import { WebSocketServer, WebSocket } from 'ws';
import os from 'os';
import http from 'http';
import https from 'https';
import { URL } from 'url';

const getLocalIP = () => {
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) return net.address;
    }
  }
  return 'localhost';
};

const HTTP_PORT = 8080;

// Create HTTP server to handle both WebSocket and Proxy requests
const server = http.createServer((req, res) => {
  // Simple CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // DuckDuckGo Proxy for CORS bypass
  if (req.url.startsWith('/proxy/ddg')) {
    const query = new URL(req.url, `http://${req.headers.host}`).searchParams.get('q');
    if (!query) {
      res.writeHead(400);
      res.end('Missing query');
      return;
    }

    const ddgUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
    https.get(ddgUrl, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    }).on('error', (err) => {
      res.writeHead(500);
      res.end('Proxy Error: ' + err.message);
    });
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

const wss = new WebSocketServer({ server });

console.log(`[HIVE P2P] Active! Local Network IP: ws://${getLocalIP()}:${HTTP_PORT}`);
console.log(`[NETWORK PROXY] Active at http://${getLocalIP()}:${HTTP_PORT}/proxy/ddg?q=...`);

wss.on('connection', (ws) => {
  console.log('Client connected to Hive Sync');

  ws.on('message', (message) => {
    try {
      const payload = JSON.parse(message);
      wss.clients.forEach((client) => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(payload));
        }
      });
    } catch (e) {
      console.error('Failed to parse broadcast:', e);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

server.listen(HTTP_PORT, '0.0.0.0');
