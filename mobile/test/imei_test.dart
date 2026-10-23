import 'package:devicetrust/core/format.dart';
import 'package:devicetrust/core/imei.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Imei.validate', () {
    test('accepts a valid Luhn IMEI', () {
      expect(Imei.validate('490154203237518'), isNull);
      expect(Imei.checkDigit('49015420323751'), 8);
    });

    test('rejects wrong check digit, length, letters and repeated digits', () {
      expect(Imei.validate('490154203237519'), contains('Check digit'));
      expect(Imei.validate('4901542032375'), contains('15 digits'));
      expect(Imei.validate('49015420323751X'), contains('digits only'));
      expect(Imei.validate('111111111111111'), contains('repeated'));
    });

    test('normalises spaces and dashes', () {
      expect(Imei.validate('4901 5420 3237 518'), isNull);
      expect(Imei.normalize('49-015420-323751-8'), '490154203237518');
    });
  });

  group('Imei.extractFromText (OCR)', () {
    test('finds valid IMEIs in label text and ignores invalid numbers', () {
      const text = 'IMEI1: 490154203237518\nIMEI2: 35-209900-176148-1\nS/N R58M123456 EAN 8806090123456 IMEI: 490154203237519';
      final found = Imei.extractFromText(text);
      expect(found, contains('490154203237518'));
      expect(found, contains('352099001761481'));
      expect(found, isNot(contains('490154203237519')));
    });
  });

  test('formatImei groups in quads', () {
    expect(formatImei('356982114092881'), '3569 8211 4092 881');
  });

  test('formatPkr', () {
    expect(formatPkr(245000), 'PKR 245,000');
  });
}
