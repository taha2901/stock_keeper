import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/cubits/list_cubits.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/excel_service.dart';
import 'package:stock_keeper/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('balance report + PDF output', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('stock_rep');
    AppDb.dir = tmp.path;
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
    final r = Repo.i;

    final a = await r.saveItem(const Item(name: 'فلانج ادابتور 160 مم', code: 'IFLA160.16', nameEn: 'HDPE BF FLANGE ADAPTOR'));
    final b = await r.saveItem(const Item(name: 'ماسورة HDPE 200 مم (D9R-D-S109) لشهر', unit: 'متر', code: '[P8-4BL-200-16-12]', nameEn: 'OD: 200mm HDPE PIPES SDR11 (Blue Stripes)'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'سند'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'موقع مكة - العوالي'));
    final rec = await r.saveParty(const Party(type: PartyType.recipient, name: 'أحمد علي'));

    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 8, 26), partyId: sup.id, refNo: '261040', lines: [VoucherLine(a, 10, '', 20), VoucherLine(b, 200, '', 17.1)]));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 9, 5), partyId: sup.id, lines: [VoucherLine(a, 5)]));
    final out = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 9, 20), partyId: site.id, recipientId: rec.id, notes: 'صرف للموقع', lines: [VoucherLine(a, 3, 'عاجل'), VoucherLine(b, 50.5)]));
    await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 10, 2), partyId: site.id, lines: [VoucherLine(b, 10)]));

    // September only: opening is August, October is excluded
    final rows = await r.balanceReport(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    final fa = rows.firstWhere((x) => x.item.id == a.id);
    final fb = rows.firstWhere((x) => x.item.id == b.id);
    expect([fa.opening, fa.inQty, fa.outQty, fa.closing], [10, 5, 3, 12]);
    expect([fb.opening, fb.inQty, fb.outQty, fb.closing], [200, 0, 50.5, 149.5]);
    final all = await r.balanceReport();
    expect(all.firstWhere((x) => x.item.id == b.id).closing, 139.5);

    // filters: supplier + invoice no + date on inbound, site + recipient on outbound
    final sup2 = await r.saveParty(const Party(type: PartyType.supplier, name: 'الاتحاد'));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 9, 10), partyId: sup2.id, refNo: 'WH/OUT/14151', lines: [VoucherLine(a, 7)]));

    final fromSanad = await r.movements(type: VType.inbound, partyId: sup.id);
    expect(fromSanad.length, 3);
    final grouped = groupMoves(fromSanad);
    final ga = grouped.firstWhere((g) => g.item == a.name);
    expect([ga.total, ga.times], [15, 2]);
    expect(ga.last, DateTime(2026, 9, 5));

    final sept = await r.movements(type: VType.inbound, partyId: sup.id, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(sept.single.qty, 5);
    expect((await r.movements(type: VType.inbound, ref: '14151')).single.party, 'الاتحاد');
    expect((await r.movements(type: VType.outbound, recipientId: rec.id)).length, 2);
    expect((await r.movements(type: VType.outbound, partyId: site.id)).length, 3);
    expect(await r.movements(type: VType.outbound, partyId: sup.id), isEmpty);

    final preview = await Directory('build/pdf_preview').create(recursive: true);
    final voucher = await PdfService.voucherBytes(out);
    final table = await PdfService.tableBytes('تقرير الرصيد', 'من 01/09/2026 إلى 30/09/2026',
        const ['الصنف', 'الوحدة', 'رصيد أول المدة', 'الوارد', 'الصادر', 'رصيد آخر المدة'],
        [for (final x in rows) [x.item.name, x.item.unit, x.opening, x.inQty, x.outQty, x.closing]]);
    await File('${preview.path}/voucher.pdf').writeAsBytes(voucher);
    await File('${preview.path}/table.pdf').writeAsBytes(table);
    expect(String.fromCharCodes(table.sublist(0, 4)), '%PDF');

    expect(ExcelService.table('x', const ['a', 'b'], [[DateTime(2026), null]]).isNotEmpty, isTrue);
    await AppDb.close();
    await tmp.delete(recursive: true);
  });
}

