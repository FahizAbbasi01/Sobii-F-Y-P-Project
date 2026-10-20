const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const DEFAULT_PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
const ROOT_DIR = __dirname;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.md': 'text/markdown; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf'
};

const ROUTE_ALIASES = {
  '/': '/index.html',
  '/splash': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_splash_screen/code.html',
  '/onboarding': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_onboarding/code.html',
  '/login': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_login_registration/code.html',
  '/auth': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_login_registration/code.html',
  '/home': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_home_marketplace/code.html',
  '/marketplace': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_home_marketplace/code.html',
  '/design': '/stitch_devicetrust_mobile_marketplace_ui/devicetrust_mobile_registry/DESIGN.md'
};

const server = http.createServer((req, res) => {
  // CORS & Security headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url);
  let pathname = decodeURIComponent(parsedUrl.pathname);

  // Check route aliases
  if (ROUTE_ALIASES[pathname]) {
    pathname = ROUTE_ALIASES[pathname];
  }

  // Prevent directory traversal attacks
  const safePath = path.normalize(pathname).replace(/^(\.\.[\/\\])+/, '');
  let filePath = path.join(ROOT_DIR, safePath);

  fs.stat(filePath, (err, stats) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`
        <!DOCTYPE html>
        <html>
        <head><title>404 Not Found - DeviceTrust</title><meta name="viewport" content="width=device-width, initial-scale=1.0"/></head>
        <body style="font-family: system-ui, sans-serif; background: #0b1528; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0;">
          <div style="text-align: center; max-width: 420px; padding: 2rem;">
            <h1 style="font-size: 2.5rem; margin-bottom: 0.5rem; color: #226afc;">404</h1>
            <p style="color: #94a3b8; margin-bottom: 1.5rem;">The requested file was not found: <code>${pathname}</code></p>
            <a href="/" style="display: inline-block; background: #226afc; color: white; padding: 0.75rem 1.5rem; border-radius: 0.75rem; text-decoration: none; font-weight: 600;">Go to DeviceTrust Studio</a>
          </div>
        </body>
        </html>
      `);
      return;
    }

    if (stats.isDirectory()) {
      filePath = path.join(filePath, 'index.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end(`500 Internal Server Error: ${readErr.message}`);
        return;
      }
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    });
  });
});

function startServer(port) {
  server.listen(port, () => {
    console.log('\n============================================================');
    console.log('   DeviceTrust Mobile Marketplace Server Running Locally');
    console.log('============================================================\n');
    console.log(`   Interactive Studio : http://localhost:${port}/`);
    console.log(`   Splash Screen      : http://localhost:${port}/splash`);
    console.log(`   Onboarding         : http://localhost:${port}/onboarding`);
    console.log(`   Login & Register   : http://localhost:${port}/login`);
    console.log(`   Home Marketplace   : http://localhost:${port}/home`);
    console.log(`   Design System      : http://localhost:${port}/design\n`);
    console.log('   Press Ctrl+C to stop the server.\n');
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.log(`Port ${port} is in use, trying port ${port + 1}...`);
      startServer(port + 1);
    } else {
      console.error('Server error:', err);
    }
  });
}

startServer(DEFAULT_PORT);
