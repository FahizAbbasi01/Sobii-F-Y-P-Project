import 'package:intl/intl.dart';

final _pkr = NumberFormat.decimalPattern('en_US');

/// "PKR 245,000"
String formatPkr(num? value) => value == null ? 'PKR —' : 'PKR ${_pkr.format(value.round())}';

/// "3569 8211 4092 881" (quad grouping per DESIGN.md)
String formatImei(String imei) {
  final b = StringBuffer();
  for (var i = 0; i < imei.length; i++) {
    if (i > 0 && i % 4 == 0) b.write(' ');
    b.write(imei[i]);
  }
  return b.toString();
}

String formatDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

String formatDateTime(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

String timeAgo(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(iso);
}

const conditionLabels = {
  'new': 'New',
  'like_new': 'Like new',
  'good': 'Good',
  'fair': 'Fair',
  'poor': 'Poor',
};

String conditionLabel(String? c) => conditionLabels[c] ?? (c ?? '');

const pakistanCities = [
  'Lahore', 'Karachi', 'Islamabad', 'Rawalpindi', 'Faisalabad', 'Multan',
  'Peshawar', 'Quetta', 'Sialkot', 'Gujranwala', 'Hyderabad', 'Abbottabad',
];
