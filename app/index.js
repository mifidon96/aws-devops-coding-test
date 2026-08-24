'use strict';

/**
 * Node.js WebAPI on AWS Lambda, behind API Gateway (HTTP API, payload v2.0).
 *
 * Deliberately dependency-light:
 *  - No Express. API Gateway already delivers a parsed request; a small
 *    route map avoids bundling a framework into every cold start.
 *  - The AWS SDK v3 is provided by the nodejs20.x runtime, so it is not
 *    packaged with the function.
 *  - `mssql` is the ONLY npm dependency, and it is loaded lazily inside the
 *    database routes. This means `terraform apply` alone gives a working
 *    /health endpoint before the pipeline has ever run `npm ci` - database
 *    routes return 503 with a clear message until the first pipeline deploy.
 *
 * Warm-start reuse: the secret and the connection pool are cached in module
 * scope, so repeat invocations on a warm container skip both the Secrets
 * Manager call and the connection handshake.
 */

const {
  SecretsManagerClient,
  GetSecretValueCommand,
} = require('@aws-sdk/client-secrets-manager');

const SECRET_NAME = process.env.DB_SECRET_NAME;
const DB_NAME = process.env.DB_NAME || 'master';

const secretsClient = new SecretsManagerClient({});

let cachedSecret = null;
let cachedPool = null;

/** Small helper: consistent JSON responses. */
const json = (statusCode, body) => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});

/**
 * Fetch and cache the database credentials.
 * This call resolves through the Secrets Manager VPC endpoint - it never
 * leaves the VPC, which is why the design needs no NAT Gateway.
 */
async function getSecret() {
  if (cachedSecret) return cachedSecret;

  const response = await secretsClient.send(
    new GetSecretValueCommand({ SecretId: SECRET_NAME })
  );

  cachedSecret = JSON.parse(response.SecretString);
  return cachedSecret;
}

/**
 * Lazily require the SQL driver so a missing dependency degrades the database
 * routes rather than crashing the whole function at import time.
 */
function loadDriver() {
  try {
    return require('mssql');
  } catch {
    return null;
  }
}

async function getPool() {
  if (cachedPool) return cachedPool;

  const sql = loadDriver();
  if (!sql) {
    const err = new Error(
      "SQL driver not bundled. Deploy via the pipeline (npm ci packages it)."
    );
    err.code = 'DRIVER_MISSING';
    throw err;
  }

  const secret = await getSecret();

  cachedPool = await new sql.ConnectionPool({
    server: secret.host,
    port: Number(secret.port),
    user: secret.username,
    password: secret.password,
    database: DB_NAME,
    options: {
      encrypt: true,
      // Dev shortcut: skips CA chain validation. Production should import
      // the regional RDS CA bundle and set this to false.
      trustServerCertificate: true,
      connectTimeout: 10000,
    },
  }).connect();

  return cachedPool;
}

/** Creates the demo table if it does not exist yet. */
async function ensureSchema(pool) {
  await pool.request().query(`
    IF NOT EXISTS (SELECT 1 FROM sysobjects WHERE name = 'items' AND xtype = 'U')
    CREATE TABLE items (
      id         INT IDENTITY(1,1) PRIMARY KEY,
      name       NVARCHAR(200) NOT NULL,
      created_at DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    )
  `);
}

/** Parses a JSON request body, handling API Gateway base64 encoding. */
function parseBody(event) {
  if (!event.body) return null;
  const raw = event.isBase64Encoded
    ? Buffer.from(event.body, 'base64').toString('utf8')
    : event.body;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/* -------------------------------------------------------------------------- */
/* Routes                                                                     */
/* -------------------------------------------------------------------------- */

const routes = {
  /** Liveness - no dependencies, always answerable. */
  'GET /health': async () =>
    json(200, {
      status: 'ok',
      service: 'node-webapi',
      timestamp: new Date().toISOString(),
    }),

  /** Readiness - proves VPC routing, security groups and credentials work. */
  'GET /health/db': async () => {
    const pool = await getPool();
    const result = await pool.request().query('SELECT 1 AS ok');
    return json(200, { status: 'ok', database: DB_NAME, result: result.recordset[0] });
  },

  'GET /items': async () => {
    const pool = await getPool();
    await ensureSchema(pool);
    const result = await pool
      .request()
      .query('SELECT id, name, created_at FROM items ORDER BY id DESC');
    return json(200, { items: result.recordset });
  },

  'POST /items': async (event) => {
    const body = parseBody(event);
    if (!body || typeof body.name !== 'string' || !body.name.trim()) {
      return json(400, { error: "Field 'name' is required" });
    }

    const sql = loadDriver();
    const pool = await getPool();
    await ensureSchema(pool);

    // Parameterised input - never string-concatenate SQL.
    const result = await pool
      .request()
      .input('name', sql.NVarChar(200), body.name.trim())
      .query(
        'INSERT INTO items (name) OUTPUT INSERTED.id, INSERTED.name, INSERTED.created_at VALUES (@name)'
      );

    return json(201, { item: result.recordset[0] });
  },
};

/* -------------------------------------------------------------------------- */
/* Handler                                                                    */
/* -------------------------------------------------------------------------- */

exports.handler = async (event) => {
  const method = event.requestContext?.http?.method || 'GET';
  const path = event.rawPath || '/';
  const key = `${method} ${path}`;

  const route = routes[key];

  if (!route) {
    return json(404, { error: 'Not found', path: key, available: Object.keys(routes) });
  }

  try {
    return await route(event);
  } catch (err) {
    if (err.code === 'DRIVER_MISSING') {
      console.warn(JSON.stringify({ level: 'warn', message: err.message, path: key }));
      return json(503, { error: err.message });
    }

    console.error(JSON.stringify({ level: 'error', message: err.message, path: key }));
    return json(500, { error: 'Internal server error' });
  }
};
