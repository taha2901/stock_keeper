import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../data/models.dart';

class ExcelService {
  /// Columns of the full-inbound workbook: one row per voucher line.
  static const voucherHeaders = [
    'المورد', 'التاريخ', 'رقم الفاتورة', 'رقم الرخصة', 'الصنف', 'الكود', 'الوحدة', 'الكمية', 'السعر',
  ];

  /// Builds an inbound workbook from vouchers (each voucher = a group of rows).
  static Uint8List vouchersWorkbook(List<List<Object?>> rows) => table('الوارد', voucherHeaders, rows);

  static DateTime? _parseDate(CellValue? v, String text) {
    if (v is DateCellValue) return v.asDateTimeLocal();
    if (v is DateTimeCellValue) return v.asDateTimeLocal();
    final t = text.trim();
    if (t.isEmpty) return null;
    for (final f in ['dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd', 'dd-MM-yyyy']) {
      try {
        return DateFormat(f).parseStrict(t);
      } catch (_) {}
    }
    return null;
  }

  /// Reads a full-inbound workbook into vouchers, grouping lines that share the
  /// same supplier + invoice number + date. Unreadable rows go into [skipped].
  static List<ImportVoucher> parseVouchers(Uint8List bytes, {List<String>? skipped}) {
    final sheet = Excel.decodeBytes(bytes).tables.values.first;
    final groups = <String, List<ImportRow>>{};
    final meta = <String, (String, DateTime, String, String)>{}; // supplier, date, ref, license
    for (final (i, row) in sheet.rows.skip(1).indexed) {
      String cell(int c) => c < row.length ? _text(row[c]?.value) : '';
      CellValue? raw(int c) => c < row.length ? row[c]?.value : null;
      final supplier = cell(0);
      final date = _parseDate(raw(1), cell(1));
      final name = cell(4);
      final qty = parseNum(cell(7));
      final blank = [supplier, cell(1), cell(2), name, cell(7)].every((e) => e.trim().isEmpty);
      if (blank) continue;
      if (supplier.trim().isEmpty || date == null || name.trim().isEmpty || qty == null) {
        skipped?.add('صف ${i + 2}: ${name.isEmpty ? (supplier.isEmpty ? cell(1) : supplier) : name}');
        continue;
      }
      final ref = cell(2), license = cell(3);
      final key = '${supplier.trim().toLowerCase()}|${ref.trim().toLowerCase()}|${DateFormat('yyyy-MM-dd').format(date)}';
      groups.putIfAbsent(key, () => []);
      meta.putIfAbsent(key, () => (supplier.trim(), date, ref.trim(), license.trim()));
      if (license.trim().isNotEmpty) {
        final m = meta[key]!;
        if (m.$4.isEmpty) meta[key] = (m.$1, m.$2, m.$3, license.trim());
      }
      groups[key]!.add(ImportRow(name.trim(), qty, cell(6).trim(), '', parseNum(cell(8)), cell(5).trim()));
    }
    return [
      for (final e in groups.entries)
        ImportVoucher(supplier: meta[e.key]!.$1, date: meta[e.key]!.$2, ref: meta[e.key]!.$3, license: meta[e.key]!.$4, lines: e.value),
    ];
  }

  static const templateHeaders = ['الصنف (الاسم أو الكود)', 'الكمية', 'الوحدة (اختياري)', 'ملاحظة (اختياري)', 'السعر (اختياري)'];

  /// Template the warehouse keeper fills to import many lines at once.
  static Uint8List template() => table('الأصناف', templateHeaders, [
        ['فلانج ادابتور 160 مم', 4, 'قطعة', '', 37.75],
        ['ماسورة HDPE 200 مم SDR11', 50, 'متر', '', null],
      ]);

  /// Reads the first sheet: column A = item, B = qty, C = unit, D = note, E = price. Row 1 is the header.
  /// Rows with an item or quantity that can't be read are added to [skipped].
  static List<ImportRow> parse(Uint8List bytes, {List<String>? skipped}) {
    final sheet = Excel.decodeBytes(bytes).tables.values.first;
    final out = <ImportRow>[];
    for (final (i, row) in sheet.rows.skip(1).indexed) {
      String cell(int c) => c < row.length ? _text(row[c]?.value) : '';
      final name = cell(0);
      final qty = parseNum(cell(1));
      if (name.isEmpty || qty == null) {
        if (name.isNotEmpty || cell(1).isNotEmpty) skipped?.add('صف ${i + 2}: ${name.isEmpty ? cell(1) : name}');
        continue;
      }
      out.add(ImportRow(name, qty, cell(2), cell(3), parseNum(cell(4))));
    }
    return out;
  }

  static String _text(CellValue? v) => switch (v) {
        null => '',
        TextCellValue(:final value) => (value.text ?? value.toString()).trim(),
        IntCellValue(:final value) => '$value',
        DoubleCellValue(:final value) => '$value',
        _ => v.toString().trim(),
      };

  /// Builds a right-to-left workbook with one sheet.
  static Uint8List table(String sheetName, List<String> headers, List<List<Object?>> rows) {
    final excel = Excel.createExcel();
    final def = excel.getDefaultSheet()!;
    excel.rename(def, sheetName);
    final s = excel[sheetName];
    s.isRTL = true;
    final head = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#BBD2F4'));
    s.appendRow(headers.map(TextCellValue.new).toList());
    for (var c = 0; c < headers.length; c++) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = head;
      final longest = [headers[c].length, ...rows.map((r) => c >= r.length ? 0 : (r[c] is DateTime ? 10 : '${r[c] ?? ''}'.length))].reduce((a, b) => a > b ? a : b);
      s.setColumnWidth(c, (longest + 3).clamp(10, 60).toDouble());
    }
    for (final r in rows) {
      s.appendRow(r.map<CellValue?>((v) => switch (v) {
            null => null,
            int x => IntCellValue(x),
            double x => DoubleCellValue(x),
            DateTime x => TextCellValue(fmtDate(x)),
            // a line break doesn't show in a cell without wrapping: keep both parts readable
            _ => TextCellValue('$v'.replaceAll('\n', ' | ')),
          }).toList());
    }
    return _forceRtl(excel.encode()!);
  }

  /// The excel package drops the sheet's right-to-left flag when saving, so set it in the file.
  static Uint8List _forceRtl(List<int> bytes) {
    final out = zip.Archive();
    for (final f in zip.ZipDecoder().decodeBytes(bytes).files) {
      if (f.isFile && f.name.startsWith('xl/worksheets/sheet')) {
        final xml = utf8.encode(utf8.decode(f.content as List<int>).replaceFirst('<sheetView ', '<sheetView rightToLeft="1" '));
        out.addFile(zip.ArchiveFile(f.name, xml.length, xml));
      } else {
        out.addFile(f);
      }
    }
    return Uint8List.fromList(zip.ZipEncoder().encode(out)!);
  }
}
