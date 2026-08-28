import { Pool, types } from 'pg';
import { poolOptions } from './config.js';
import { logger, recordMetric } from './observability.js';

// PostgreSQL DATE is a calendar value, not an instant. Keep it as YYYY-MM-DD
// so JSON serialization cannot shift it to the previous day in UTC.
types.setTypeParser(1082, (value) => value);

export const pool = new Pool(poolOptions);
pool.on('error', (error) => {
  recordMetric('xiangshang_db_pool_errors_total');
  logger.error('db.pool_error', { error: error.message });
});
export const query = (text, params = []) => pool.query(text, params);
