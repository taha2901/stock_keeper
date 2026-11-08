import 'package:intl/intl.dart';

import '../data/models.dart';

final _show = DateFormat('dd/MM/yyyy');
final _store = DateFormat('yyyy-MM-dd');
final _qty = NumberFormat('#,##0.###', 'en');

String fmtDate(DateTime d) => _show.format(d);
String dbDate(DateTime d) => _store.format(d);
String fmtQty(num v) => _qty.format(v.abs() < 1e-6 ? 0 : v);
final _money = NumberFormat('#,##0.00', 'en');
String fmtMoney(num v) => _money.format(v);

const noPrice = 'بدون سعر';

/// "20.00", or one "qty × price" per line when FIFO took it from several prices.
String priceLabel(LineCost c, {String sep = '\n'}) {
  if (c.slices.isEmpty) return '';
  if (c.slices.length == 1) return c.slices.single.price == null ? noPrice : fmtMoney(c.slices.single.price!);
  return c.slices.map((s) => '${fmtQty(s.qty)} × ${s.price == null ? noPrice : fmtMoney(s.price!)}').join(sep);
}

/// A value with a marker when part of the quantity has no price yet.
String valueLabel(double value, bool missing) => missing ? (value == 0 ? noPrice : '${fmtMoney(value)} *') : fmtMoney(value);

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Accepts Arabic-Indic digits and comma decimals ("١٢٫٥", "12,5").
double? parseNum(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = s.trim();
  for (var i = 0; i < 10; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  t = t.replaceAll('٫', '.').replaceAll('٬', ',');
  // 1,000 and 1,250,000.5 are thousands; 12,5 is a decimal comma
  t = RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(t) ? t.replaceAll(',', '') : t.replaceAll(',', '.');
  final v = double.tryParse(t);
  return v == null || !v.isFinite ? null : v;
}
