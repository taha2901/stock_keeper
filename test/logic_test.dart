import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/core/format.dart';
import 'package:stock_keeper/cubits/voucher_form_cubit.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/excel_service.dart';

void main() {
  late Directory tmp;
  final r = Repo.i;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_test');
    AppDb.dir = tmp.path;
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  test('in / out / balance / ledger / validation / excel import', () async {
    final flange = await r.saveItem(const Item(name: 'فلانج ادابتور 160 مم', code: 'IFLA160.16'));
    final pipe = await r.saveItem(const Item(name: 'ماسورة HDPE 200 مم', unit: 'متر', minQty: 50));
    expect(() => r.saveItem(const Item(name: 'فلانج ادابتور 160 مم')), throwsA(isA<String>()));

    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'سند'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'موقع مكة - العوالي'));

    final in1 = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 8, 26), partyId: sup.id, refNo: '261040',
        lines: [VoucherLine(flange, 4), VoucherLine(pipe, 200)]));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 9, 14), partyId: sup.id, lines: [VoucherLine(flange, 10)]));
    final out1 = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 9, 20), partyId: site.id, lines: [VoucherLine(pipe, 170)]));

    expect(await r.balance(flange.id!), 14);
    expect(await r.balance(pipe.id!), 30);
    expect((await r.voucher(in1)).number, 1);
    expect((await r.voucher(out1)).number, 1); // numbering is per type

    final ledger = await r.ledger(pipe.id!);
    expect(ledger.map((e) => e.balance).toList(), [200, 30]);

    final stock = await r.stock();
    expect(stock.firstWhere((s) => s.item.id == pipe.id).low, isTrue); // 30 <= min 50

    // issuing more than the balance is blocked
    final f = VoucherFormCubit(VType.outbound, null);
    f.setParty(site);
    await f.addItem(pipe);
    f.setQty(f.state.lines.single.uid, 31);
    await f.save();
    expect(f.state.error, contains('أكبر من الرصيد'));
    f.setQty(f.state.lines.single.uid, 30);
    await f.save();
    expect(f.state.savedId, isNotNull);
    expect(await r.balance(pipe.id!), 0);

    // editing a voucher excludes its own lines from the available balance
    final edit = VoucherFormCubit(VType.outbound, f.state.savedId);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(edit.state.lines.single.available, 30);

    // excel: template parses, and items match by name or by supplier code inside the text
    expect(ExcelService.parse(ExcelService.template()).length, 2);
    final xl = ExcelService.table('x', ExcelService.templateHeaders, [
      ['[IFLA160.16] OD:160mm HDPE BF FLANGE ADAPTOR', 3, '', ''],
      ['صنف مش موجود', 2, 'طن', ''],
      ['', 5, '', ''],
    ]);
    final rows = ExcelService.parse(xl);
    expect(rows.length, 2);
    final g = VoucherFormCubit(VType.outbound, null);
    final missing = await g.importRows(rows);
    expect(missing.single.name, 'صنف مش موجود');
    expect(g.state.lines.single.item.id, flange.id);
    expect(g.state.lines.single.qty, 3);

    final mv = await r.movements(type: VType.inbound, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(mv.length, 1);
    expect(parseNum('١٢٫٥'), 12.5);
    expect(() => r.deleteItem(flange.id!), throwsA(isA<String>()));
  });
}
