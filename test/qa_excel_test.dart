import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_keeper/services/excel_service.dart';

/// Writes files for a check in real Excel, and reads files Excel itself produced.
void main() {
  test('write app exports', () async {
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/template.xlsx').writeAsBytes(ExcelService.template());
    await File('build/qa/report.xlsx').writeAsBytes(ExcelService.table('تقرير الوارد', const ['التاريخ', 'الصنف', 'الكمية', 'القيمة'], [
      [DateTime(2026, 11, 8), 'فلانج 160', 4, 151.0],
      ['الإجمالي', null, null, 151.0],
    ]));
  });

  test('read a template that was re-saved by real Excel', () async {
    final f = File('build/qa/template_excel.xlsx');
    if (!f.existsSync()) return;
    final skipped = <String>[];
    final rows = ExcelService.parse(Uint8List.fromList(await f.readAsBytes()), skipped: skipped);
    expect(rows.length, 2);
    expect(rows[0].qty, 4);
    expect(rows[0].price, 37.75);
    // quantities typed as Excel formulas can't be read; they must be reported, not lost
    expect(skipped.single, contains('بند من Excel'));
  });

  test("decode the user's real workbook without crashing", () async {
    final f = File('build/qa/real.xlsx');
    if (!f.existsSync()) return;
    final book = Excel.decodeBytes(await f.readAsBytes());
    expect(book.tables.isNotEmpty, isTrue);
    ExcelService.parse(Uint8List.fromList(await f.readAsBytes()), skipped: []);
  });
}
