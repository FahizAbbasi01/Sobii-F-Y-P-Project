const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateImei, luhnCheckDigit } = require('../src/lib/imei');

test('accepts a known-valid IMEI (Luhn)', () => {
  // 49015420323751 → check digit 8 (standard published example)
  assert.equal(luhnCheckDigit('49015420323751'), 8);
  assert.equal(validateImei('490154203237518').valid, true);
});

test('normalises spaces and dashes', () => {
  const r = validateImei('49-015420-323751-8');
  assert.equal(r.valid, true);
  assert.equal(r.imei, '490154203237518');
});

test('rejects wrong check digit, wrong length, letters, repeated digits', () => {
  assert.match(validateImei('490154203237519').reason, /check digit/);
  assert.match(validateImei('49015420323751').reason, /15 digits/);
  assert.match(validateImei('4901542032375A8').reason, /digits only/);
  assert.match(validateImei('000000000000000').reason, /repeated/);
  assert.equal(validateImei(null).valid, false);
});
