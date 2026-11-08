import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/excel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp; final r = Repo.i;
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_imp');
    AppDb.dir = tmp.path; await AppDb.open(); await r.loadCurrentWarehouse();
  });
  tearDownAll(() async { await AppDb.close(); await tmp.delete(recursive: true); });

  test('workbook round-trips: generate -> parse -> import, grouped by invoice, into a chosen warehouse', () async {
    final wh = await r.saveWarehouse(const Warehouse(name: 'مخزن الاستيراد'));
    // two vouchers: SANAD (priced) and Union (one line no price), spread over rows
    final rows = <List<Object?>>[
      ['سند', DateTime(2026, 8, 26), '261040', 'LIC-1', 'فلانج 160', '', 'قطعة', 4, 37.75],
      ['سند', DateTime(2026, 8, 26), '261040', '', 'رينج 160', '', 'قطعة', 4, 100.0],
      ['الاتحاد', DateTime(2026, 9, 14), 'WH/OUT/14151', '', 'ماسورة 200', '[P8-4BL-200-16-12]', 'متر', 200, null],
      ['', DateTime(2026, 1, 1), '', '', '', '', '', 'مش رقم', null], // bad row -> skipped
    ];
    final bytes = ExcelService.vouchersWorkbook(rows);
    final skipped = <String>[];
    final vs = ExcelService.parseVouchers(bytes, skipped: skipped);
    expect(vs.length, 2);
    expect(skipped.length, 1);
    final sanad = vs.firstWhere((v) => v.supplier == 'سند');
    expect(sanad.lineCount, 2);
    expect(sanad.ref, '261040');
    expect(sanad.license, 'LIC-1');

    final res = await r.importVouchers(vs, wh.id!);
    expect(res['vouchers'], 2);
    expect(res['lines'], 3);
    expect(res['newSuppliers'], 2);

    // balances landed in the chosen warehouse, with prices
    expect(await r.balance((await r.allItems()).firstWhere((i) => i.name == 'فلانج 160').id!, warehouseId: wh.id), 4);
    final v = (await r.vouchers(VType.inbound, warehouseId: wh.id)).firstWhere((x) => x.refNo == '261040');
    expect(v.total, closeTo(4 * 37.75 + 4 * 100, 0.01));
    expect(v.licenseNo, 'LIC-1');
    // union item matched by code, no price -> missing
    final union = (await r.vouchers(VType.inbound, warehouseId: wh.id)).firstWhere((x) => x.refNo == 'WH/OUT/14151');
    expect(union.missing, isTrue);

    // nothing leaked into the default warehouse
    expect((await r.stock(warehouseId: r.currentWarehouseId)).where((s) => s.item.name == 'فلانج 160'), isEmpty);
  });
}
