import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ageMonthsFromBirthDate, BUSINESS_TIME_ZONE } from '../src/age.js';

test('age model uses a date-only China business calendar and rejects invalid dates', () => {
  assert.equal(BUSINESS_TIME_ZONE, 'Asia/Shanghai');
  assert.equal(ageMonthsFromBirthDate('2018-08-22', new Date('2026-08-22T15:59:00.000Z')), 96);
  // 23:59 UTC is 07:59 the next day in Shanghai: the birthday has arrived.
  assert.equal(ageMonthsFromBirthDate('2018-08-22', new Date('2026-08-22T16:00:00.000Z')), 96);
  assert.equal(ageMonthsFromBirthDate('2018-08-23', new Date('2026-08-22T15:59:00.000Z')), 95);
  assert.equal(ageMonthsFromBirthDate('2026-02-31', new Date('2026-08-22T00:00:00.000Z')), null);
  assert.equal(ageMonthsFromBirthDate('2999-01-01', new Date('2026-08-22T00:00:00.000Z')), null);
});
