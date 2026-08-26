import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GROWTH_ALGORITHM_VERSION, scoreGrowth } from '../src/growthScoring.js';

const now = new Date('2026-08-22T08:00:00.000Z');

test('growth scorer uses business date window and rejects impossible dates', () => {
  const report = scoreGrowth({ period: 'week', checkInDates: ['2026-08-16', '2026-08-17', '2026-02-31', 'not-a-date'], now });
  assert.equal(report.algorithm, GROWTH_ALGORITHM_VERSION);
  assert.equal(report.activeDays, 2);
  assert.equal(report.consistencyPercent, 50);
});

test('growth scorer fails closed on an invalid now value', () => {
  const report = scoreGrowth({
    period: 'week',
    checkInDates: ['2026-08-20'],
    planDates: ['2026-08-21'],
    now: new Date('not-a-date')
  });
  assert.equal(report.activeDays, 0);
  assert.equal(report.consistencyPercent, 0);
});

test('growth scorer never treats unpublished score as zero', () => {
  const report = scoreGrowth({ period: 'week', checkInDates: ['2026-08-18', '2026-08-19', '2026-08-20', '2026-08-21'], totalScore: null, now });
  assert.equal(report.planTitle, '均衡成长计划');
  assert.equal(report.assessmentCount, 0);
});

test('growth scorer fails closed on malformed totals and counts plan dates once', () => {
  const report = scoreGrowth({ period: 'month', planDates: ['2026-08-01', '2026-08-01', '2026-08-02'], assessmentCount: -3.4, totalScore: Number.NaN, now });
  assert.equal(report.planDays, 2);
  assert.equal(report.activeDays, 2);
  assert.equal(report.assessmentCount, 0);
  assert.ok(report.consistencyPercent >= 0 && report.consistencyPercent <= 100);
});

test('growth scorer normalizes an unknown period to the weekly contract', () => {
  assert.equal(scoreGrowth({ period: 'quarter', now }).period, 'week');
});
