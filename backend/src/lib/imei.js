/**
 * IMEI validation.
 * An IMEI is 15 digits: 8-digit TAC + 6-digit serial + 1 Luhn check digit.
 * We only accept 15-digit IMEIs with a valid Luhn check digit. We do NOT claim
 * anything about whether the TAC is allocated by GSMA — that needs an external
 * database we don't have.
 */

function normalizeImei(input) {
  if (typeof input !== 'string' && typeof input !== 'number') return '';
  return String(input).replace(/[\s\-./]/g, '');
}

function luhnCheckDigit(first14) {
  let sum = 0;
  for (let i = 0; i < 14; i += 1) {
    let d = Number(first14[i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return (10 - (sum % 10)) % 10;
}

/**
 * @returns {{ valid: boolean, imei: string, reason?: string }}
 */
function validateImei(input) {
  const imei = normalizeImei(input);
  if (!/^\d+$/.test(imei)) return { valid: false, imei, reason: 'IMEI must contain digits only' };
  if (imei.length !== 15) return { valid: false, imei, reason: 'IMEI must be exactly 15 digits' };
  if (/^(\d)\1{14}$/.test(imei)) return { valid: false, imei, reason: 'IMEI cannot be a single repeated digit' };
  if (luhnCheckDigit(imei.slice(0, 14)) !== Number(imei[14])) {
    return { valid: false, imei, reason: 'IMEI check digit is invalid' };
  }
  return { valid: true, imei };
}

module.exports = { normalizeImei, luhnCheckDigit, validateImei };
