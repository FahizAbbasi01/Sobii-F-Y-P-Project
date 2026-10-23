require('dotenv').config({ quiet: true });

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

const nodeEnv = process.env.NODE_ENV || 'development';

const env = {
  nodeEnv,
  isTest: nodeEnv === 'test',
  port: Number(process.env.PORT || 4000),
  databaseUrl: nodeEnv === 'test'
    ? (process.env.TEST_DATABASE_URL || required('DATABASE_URL'))
    : required('DATABASE_URL'),
  databaseSsl: process.env.DATABASE_SSL === 'true',
  jwtSecret: required('JWT_ACCESS_SECRET'),
  accessTokenTtl: process.env.ACCESS_TOKEN_TTL || '30m',
  refreshTokenDays: Number(process.env.REFRESH_TOKEN_DAYS || 30),
  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:5173').split(',').map((s) => s.trim()).filter(Boolean),
  // Storage: 'supabase' in production, 'local' for development without Supabase.
  storageDriver: process.env.STORAGE_DRIVER || 'local',
  localUploadDir: process.env.LOCAL_UPLOAD_DIR || 'uploads',
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  supabaseBucket: process.env.SUPABASE_STORAGE_BUCKET || 'devicetrust-private',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || `http://localhost:${process.env.PORT || 4000}`,
};

if (env.jwtSecret.length < 32) {
  throw new Error('JWT_ACCESS_SECRET must be at least 32 characters');
}
if (env.storageDriver === 'supabase' && (!env.supabaseUrl || !env.supabaseServiceRoleKey)) {
  throw new Error('STORAGE_DRIVER=supabase requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY');
}

module.exports = env;
