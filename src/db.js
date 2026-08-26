import { Pool } from 'pg';
import { poolOptions } from './config.js';
import { logger, recordMetric } from './observability.js';

export const pool = new Pool(poolOptions);
pool.on('error', (error) => {
  recordMetric('xiangshang_db_pool_errors_total');
  logger.error('db.pool_error', { error: error.message });
});
export const query = (text, params = []) => pool.query(text, params);
