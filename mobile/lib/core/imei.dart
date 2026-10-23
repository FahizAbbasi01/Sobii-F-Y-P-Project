/// Client-side IMEI checks for instant feedback. The server re-validates everything.
class Imei {
  static String normalize(String input) => input.replaceAll(RegExp(r'[\s\-./]'), '');

  static int checkDigit(String first14) {
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      var d = int.parse(first14[i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return (10 - (sum % 10)) % 10;
  }

  /// Returns null when valid, otherwise a human-readable reason.
  static String? validate(String input) {
    final imei = normalize(input);
    if (imei.isEmpty) return 'Enter the 15-digit IMEI';
    if (!RegExp(r'^\d+$').hasMatch(imei)) return 'IMEI must contain digits only';
    if (imei.length != 15) return 'IMEI must be exactly 15 digits (${imei.length} entered)';
    if (RegExp(r'^(\d)\1{14}$').hasMatch(imei)) return 'IMEI cannot be one repeated digit';
    if (checkDigit(imei.substring(0, 14)) != int.parse(imei[14])) {
      return 'Check digit is wrong — re-check the number';
    }
    return null;
  }

  static bool isValid(String input) => validate(input) == null;

  /// Pulls every Luhn-valid 15-digit IMEI out of OCR text (box labels, *#06# screens).
  static List<String> extractFromText(String text) {
    final found = <String>{};
    // Allow digits separated by spaces/dashes, as printed on many labels.
    final candidates = RegExp(r'(?:\d[\s\-]?){15,17}').allMatches(text);
    for (final m in candidates) {
      final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i + 15 <= digits.length; i++) {
        final c = digits.substring(i, i + 15);
        if (isValid(c)) found.add(c);
      }
    }
    return found.toList();
  }
}
