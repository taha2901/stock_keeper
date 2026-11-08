import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/repo.dart';

class PdfService {
  static pw.ThemeData? _theme;
  static final _headFill = PdfColor.fromHex('#BBD2F4');
  static final _arabic = RegExp(r'[\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]');
  static final _atom = RegExp(r'\d+(?:[.,]\d+)*|.', dotAll: true);
  static const _mirror = {'(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{'};

  static String _rev(String s) =>
      _atom.allMatches(s).map((m) => _mirror[m[0]!] ?? m[0]!).toList().reversed.join();

  /// The pdf package's RTL text path mirrors Latin letters (digit groups are kept).
  /// Pre-reversing the non-Arabic parts cancels that out.
  @visibleForTesting
  static String t(String s) => s.split('\n').map((line) {
        if (!_arabic.hasMatch(line)) return line;
        return line.split(' ').map((w) => _arabic.hasMatch(w) ? w : _rev(w)).join(' ');
      }).join('\n');

  static final _latin = pw.Font.helvetica();

  /// Text whose lines each get the right direction: Arabic lines go through the
  /// RTL path, lines with no Arabic are drawn plainly left-to-right.
  static pw.Widget _w(String raw, {pw.TextStyle? style, pw.TextAlign align = pw.TextAlign.center}) {
    // typographic marks that neither embedded font can draw
    final s = raw.replaceAll(RegExp('[\u2013\u2014\u2212\u2022]'), '-').replaceAll(RegExp('[\u201C\u201D\u201E]'), '"').replaceAll(RegExp('[\u2018\u2019]'), "'").replaceAll('\u2026', '...');
    pw.Widget one(String l) => _arabic.hasMatch(l)
        ? pw.Text(t(l), textDirection: pw.TextDirection.rtl, textAlign: align, style: style)
        : pw.Text(l, textDirection: pw.TextDirection.ltr, textAlign: align, style: (style ?? const pw.TextStyle()).copyWith(font: _latin));
    final lines = s.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return pw.SizedBox();
    return lines.length == 1
        ? one(lines.first)
        : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: lines.map(one).toList());
  }

  // Columns are given in reading order and flipped here, because pw.Table lays out left-to-right.
  static Map<int, pw.TableColumnWidth> _flipW(Map<int, pw.TableColumnWidth> w) => {for (final e in w.entries) w.length - 1 - e.key: e.value};

  static Future<pw.ThemeData> _loadTheme() async => _theme ??= pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf')),
        fontFallback: [pw.Font.helvetica()],
      );

  /// Built on pw.Table directly: TableHelper reserves space for wrapped lines but
  /// doesn't paint them when cells are aligned, so long item names lost text.
  static pw.Widget _table(List<String> headers, List<List<pw.Widget>> rows, Map<int, pw.TableColumnWidth> widths, {double fontSize = 12}) {
    pw.Widget cell(pw.Widget c) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4), child: c);
    return pw.Table(
      border: pw.TableBorder.all(width: .7),
      columnWidths: _flipW(widths),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _headFill),
          children: [for (final h in headers.reversed) cell(_w(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)))],
        ),
        for (final r in rows) pw.TableRow(children: [for (final c in r.reversed) cell(c)]),
      ],
    );
  }

  static Future<String> _company() => Repo.i.setting('company', 'شركة سان المتحدة للمقاولات العامة');

  static pw.Widget _header(String company) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(t(company), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Text(t('طُبع في ${fmtDate(DateTime.now())}'), style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.Divider(),
      ]);

  static pw.Widget _footer(pw.Context c) => pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Text('صفحة ${c.pageNumber} من ${c.pagesCount}', style: const pw.TextStyle(fontSize: 9)));

  /// Opens the system print dialog (with preview).
  static Future<void> printBytes(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  /// Any list/report as a PDF table. Wide tables switch to landscape.
  static Future<Uint8List> tableBytes(String title, String subtitle, List<String> headers, List<List<Object?>> rows) async {
    String cell(Object? v) => switch (v) {
          null => '',
          DateTime d => fmtDate(d),
          double d => fmtQty(d),
          _ => '$v',
        };
    final data = [for (final r in rows) r.map(cell).toList()];
    final widths = <int, pw.TableColumnWidth>{
      for (var c = 0; c < headers.length; c++)
        c: pw.FlexColumnWidth([headers[c].length, ...data.map((r) => r[c].length)].reduce((a, b) => a > b ? a : b).clamp(5, 32).toDouble()),
    };
    final company = await _company();
    final doc = pw.Document(theme: await _loadTheme());
    doc.addPage(pw.MultiPage(
      maxPages: 5000,
      pageFormat: headers.length > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.rtl,
      header: (_) => _header(company),
      footer: _footer,
      build: (_) => [
        pw.Center(child: pw.Text(t(title), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
        if (subtitle.isNotEmpty) pw.Center(child: pw.Text(t(subtitle), style: const pw.TextStyle(fontSize: 11))),
        pw.SizedBox(height: 12),
        _table(headers, [for (final r in data) [for (final c in r) _w(c, style: const pw.TextStyle(fontSize: 10))]], widths, fontSize: 10),
      ],
    ));
    return doc.save();
  }

  /// The printable receipt / issue voucher with signature boxes.
  static Future<Uint8List> voucherBytes(int id) async {
    final v = await Repo.i.voucher(id);
    final company = await _company();
    final keeper = await Repo.i.setting('keeper');
    final doc = pw.Document(theme: await _loadTheme());

    pw.Widget info(String k, String val) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.SizedBox(width: 90, child: pw.Text(k, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Expanded(child: _w(val.isEmpty ? '-' : val, align: pw.TextAlign.right)),
          ]),
        );

    pw.Widget sign(String title, String name) => pw.Expanded(
          child: pw.Column(children: [
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            name.isEmpty ? pw.Text(' ') : _w(name),
            pw.SizedBox(height: 22),
            pw.Text('التوقيع: ..........................'),
          ]),
        );

    doc.addPage(pw.MultiPage(
      maxPages: 5000,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      textDirection: pw.TextDirection.rtl,
      header: (_) => _header(company),
      footer: _footer,
      build: (_) => [
        pw.Center(child: pw.Text(t(v.title), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Column(children: [
              info('المخزن:', v.warehouseName),
              info('التاريخ:', fmtDate(v.date)),
              info('${v.type.partyType.label}:', v.partyName),
              if (v.type.isIn) info('رقم الفاتورة:', v.refNo) else info('المستلم:', v.recipientName),
            ])),
            pw.SizedBox(width: 16),
            pw.Expanded(
                child: pw.Column(children: [
              if (!v.type.isIn) info('رقم مرجعي:', v.refNo),
              if (v.licenseNo.isNotEmpty) info('رقم الرخصة:', v.licenseNo),
              info('ملاحظات:', v.notes),
            ])),
          ]),
        ),
        pw.SizedBox(height: 14),
        _table(
          const ['م', 'الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي', 'ملاحظات'],
          [
            for (var i = 0; i < v.lines.length; i++)
              [
                _w('${i + 1}'),
                _w([v.lines[i].item.name, if (v.lines[i].item.code.isNotEmpty) v.lines[i].item.code, if (v.lines[i].item.nameEn.isNotEmpty) v.lines[i].item.nameEn].join('\n')),
                _w(v.lines[i].item.unit),
                _w(fmtQty(v.lines[i].qty)),
                _w(priceLabel(v.lines[i].cost), style: const pw.TextStyle(fontSize: 10)),
                _w(valueLabel(v.lines[i].cost.value, v.lines[i].cost.missing)),
                _w(v.lines[i].note),
              ]
          ],
          {
            0: const pw.FixedColumnWidth(28),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FixedColumnWidth(46),
            3: const pw.FixedColumnWidth(50),
            4: const pw.FixedColumnWidth(78),
            5: const pw.FixedColumnWidth(72),
            6: const pw.FlexColumnWidth(1.5),
          },
        ),
        pw.SizedBox(height: 8),
        pw.Text(t('إجمالي القيمة: ${valueLabel(v.total, v.missing)} ريال'), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        if (v.missing) pw.Text('* فيه كميات بدون سعر ومش داخلة في الإجمالي', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [
          sign('أمين المستودع', keeper),
          sign(v.type.isIn ? 'المورد / المندوب' : 'المستلم', v.type.isIn ? '' : v.recipientName),
          sign('الاعتماد', ''),
        ]),
      ],
    ));
    return doc.save();
  }

  static Future<void> printVoucher(int id) async {
    final v = await Repo.i.voucher(id);
    await printBytes(await voucherBytes(id), v.title);
  }
}
