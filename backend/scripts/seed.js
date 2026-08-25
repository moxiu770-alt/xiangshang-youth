import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { promisify } from 'node:util';
import { Pool } from 'pg';

const scryptAsync = promisify(crypto.scrypt);
const password = process.env.SEED_PASSWORD || 'ChangeMe123!';
const salt = crypto.randomBytes(16).toString('hex');
const derived = (await scryptAsync(password, salt, 64)).toString('hex');
const passwordHash = `scrypt$${salt}$${derived}`;
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const client = await pool.connect();
try {
  await client.query('BEGIN');
  await client.query(await fs.readFile(new URL('../db/seed.sql', import.meta.url), 'utf8'));
  const user = await client.query(`INSERT INTO users(phone,name,password_hash) VALUES('13800000000','演示管理员',$1)
    ON CONFLICT(phone) DO UPDATE SET password_hash=EXCLUDED.password_hash,name=EXCLUDED.name RETURNING id`, [passwordHash]);
  const role = await client.query(`SELECT id FROM roles WHERE code='admin'`);
  await client.query(`INSERT INTO user_roles(user_id,role_id,school_id) VALUES($1,$2,'school-1') ON CONFLICT DO NOTHING`, [user.rows[0].id, role.rows[0].id]);
  await client.query('COMMIT');
  console.log(`Seed admin: 13800000000 / ${password}`);
} catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); await pool.end(); }
