const env = require('./config/env');
const app = require('./app');
const { pool } = require('./lib/db');

const server = app.listen(env.port, '0.0.0.0', () => {
  console.log(`DeviceTrust API listening on http://localhost:${env.port} (${env.nodeEnv}, storage: ${env.storageDriver})`);
});

function shutdown() {
  server.close(() => pool.end().then(() => process.exit(0)));
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
