import test from 'node:test';
import assert from 'node:assert/strict';
import { formatStatValue } from '../scripts/utils/stat-format.js';

test('formats thousands without trailing decimals', () => {
  assert.equal(formatStatValue(1_000), '1k');
  assert.equal(formatStatValue(12_400), '12.4k');
});

test('formats millions and billions with suffixes', () => {
  assert.equal(formatStatValue(2_000_000), '2m');
  assert.equal(formatStatValue(3_450_000_000), '3.5b');
});

test('promotes values when rounding crosses a suffix boundary', () => {
  assert.equal(formatStatValue(999_999), '1m');
  assert.equal(formatStatValue(999_950_000), '1b');
});

test('scales negative values by their magnitude', () => {
  assert.equal(formatStatValue(-1_500), '-1.5k');
  assert.equal(formatStatValue(-999_999), '-1m');
  assert.equal(formatStatValue(-2_500_000_000), '-2.5b');
});

test('keeps one decimal place below a thousand', () => {
  assert.equal(formatStatValue(12.34), '12.3');
  assert.equal(formatStatValue(4.6), '4.6');
  assert.equal(formatStatValue(999), '999');
});

test('stays on the billions suffix beyond its range', () => {
  // A characterisation test. Nothing is larger than "b" yet (audit finding 28), so this pins
  // today's output; a change to the scaling loops cannot then silently produce "1.5undefined".
  assert.equal(formatStatValue(1.5e12), '1500b');
});

test('leaves non-numeric values unchanged', () => {
  assert.equal(formatStatValue('1.2M'), '1.2M');
});

test('normalizes negative zero after rounding', () => {
  assert.equal(formatStatValue(-0.0001), '0');
});

test('returns strings for non-finite values', () => {
  assert.equal(formatStatValue(Infinity), 'Infinity');
  assert.equal(formatStatValue(-Infinity), '-Infinity');
  assert.equal(formatStatValue(NaN), 'NaN');
});
