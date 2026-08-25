const cliOptionMap = {
  application_name: 'PGAPPNAME',
  connect_timeout: 'PGCONNECT_TIMEOUT',
  options: 'PGOPTIONS',
  sslcert: 'PGSSLCERT',
  sslkey: 'PGSSLKEY',
  sslmode: 'PGSSLMODE',
  sslrootcert: 'PGSSLROOTCERT'
};

/**
 * Converts a database URL to libpq environment variables for pg_dump and
 * pg_restore. Keeping the URL out of argv avoids exposing passwords through
 * the operating system's process list.
 */
export function postgresCliEnv(databaseUrl, inheritedEnvironment = process.env) {
  let url;
  try { url = new URL(databaseUrl); } catch { throw new Error('DATABASE_URL 必须是有效的 PostgreSQL 连接地址'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error('DATABASE_URL 必须使用 postgres 或 postgresql 协议');
  const database = decodeURIComponent(url.pathname || '').replace(/^\/+/, '');
  if (!database) throw new Error('DATABASE_URL 必须包含数据库名称');
  const environment = { ...inheritedEnvironment };
  // Do not forward the URL to the child process after its parts have been
  // extracted. This keeps its password out of the operating system argv view.
  delete environment.DATABASE_URL;
  environment.PGHOST = url.hostname.replace(/^\[|\]$/g, '');
  environment.PGPORT = url.port || '5432';
  environment.PGDATABASE = database;
  if (url.username) environment.PGUSER = decodeURIComponent(url.username);
  if (url.password) environment.PGPASSWORD = decodeURIComponent(url.password);
  for (const [parameter, variable] of Object.entries(cliOptionMap)) {
    const value = url.searchParams.get(parameter);
    if (value) environment[variable] = value;
  }
  return environment;
}
