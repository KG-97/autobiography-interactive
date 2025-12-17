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

test('leaves non-numeric values unchanged', () => {
  assert.equal(formatStatValue('1.2M'), '1.2M');
});
