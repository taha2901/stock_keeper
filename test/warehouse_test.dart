import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  final r = Repo.i;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_wh');
    AppDb.dir = tmp.path;
    await AppDb.open();
    await r.loadCurrentWarehouse();
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  test('stock, FIFO prices and reports are each kept per warehouse', () async {
    final main = (await r.warehouses()).single; // the seeded "المخزن الرئيسي"
    final jeddah = await r.saveWarehouse(const Warehouse(name: 'مخزن جدة'));
    final riyadh = await r.saveWarehouse(const Warehouse(name: 'مخزن الرياض'));

    final a = await r.saveItem(const Item(name: 'ماسورة'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'مورد'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'موقع'));

    // same item, different warehouses, different prices
    await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: jeddah.id!, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, 100, '', 10)]));
    await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: riyadh.id!, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, 50, '', 20)]));
    // issue 30 from Jeddah only
    await r.saveVoucher(Voucher(type: VType.outbound, warehouseId: jeddah.id!, date: DateTime(2026, 1, 2), partyId: site.id, lines: [VoucherLine(a, 30)]));

    double bal(List<ItemStock> s) => s.firstWhere((x) => x.item.id == a.id).balance;
    double val(List<ItemStock> s) => s.firstWhere((x) => x.item.id == a.id).value;

    final jed = await r.stock(warehouseId: jeddah.id);
    final riy = await r.stock(warehouseId: riyadh.id);

    expect(bal(jed), 70); // 100 in - 30 out
    expect(val(jed), 700); // 70 @ 10
    expect(bal(riy), 50); // untouched
    expect(val(riy), 1000); // 50 @ 20

    // an empty warehouse's stock view is empty, but the full catalog is reachable
    expect((await r.stock(warehouseId: main.id)).where((x) => x.item.id == a.id), isEmpty);
    expect((await r.stock(warehouseId: main.id, includeEmpty: true)).any((x) => x.item.id == a.id), isTrue);
    expect((await r.stock(warehouseId: jeddah.id)).any((x) => x.item.id == a.id), isTrue); // has movement

    // balance of the item is per warehouse
    expect(await r.balance(a.id!, warehouseId: jeddah.id), 70);
    expect(await r.balance(a.id!, warehouseId: riyadh.id), 50);

    // Jeddah issue is valued at Jeddah's price (10), not Riyadh's (20)
    final jedMoves = await r.movements(type: VType.outbound, warehouseId: jeddah.id);
    expect(jedMoves.single.cost.value, 300);

    // ledger and reports respect the warehouse filter
    expect((await r.ledger(a.id!, warehouseId: riyadh.id)).length, 1); // only the receipt
    expect((await r.ledger(a.id!, warehouseId: jeddah.id)).length, 2);
    expect((await r.balanceReport(warehouseId: riyadh.id)).firstWhere((b) => b.item.id == a.id).closing, 50);
    expect((await r.vouchers(VType.inbound, warehouseId: jeddah.id)).length, 1);

    // numbering restarts per warehouse
    final jId = await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: jeddah.id!, date: DateTime(2026, 1, 3), partyId: sup.id, lines: [VoucherLine(a, 5, '', 10)]));
    expect((await r.voucher(jId)).number, 2); // Jeddah's 2nd receipt
    final rId = await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: riyadh.id!, date: DateTime(2026, 1, 3), partyId: sup.id, lines: [VoucherLine(a, 5, '', 20)]));
    expect((await r.voucher(rId)).number, 2); // Riyadh's own 2nd receipt
  });

  test('issuing more than the warehouse holds is blocked, even if another warehouse has stock', () async {
    final w1 = (await r.warehouses()).firstWhere((w) => w.name == 'مخزن جدة');
    final w2 = (await r.warehouses()).firstWhere((w) => w.name == 'مخزن الرياض');
    final b = await r.saveItem(const Item(name: 'صنف2'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'مورد2'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'موقع2'));
    await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: w2.id!, date: DateTime(2026, 2, 1), partyId: sup.id, lines: [VoucherLine(b, 100, '', 5)]));

    // w1 has none of صنف2; a direct save would make it negative — balance confirms 0
    expect(await r.balance(b.id!, warehouseId: w1.id), 0);
    expect(await r.balance(b.id!, warehouseId: w2.id), 100);
    final out = await r.saveVoucher(Voucher(type: VType.outbound, warehouseId: w2.id!, date: DateTime(2026, 2, 2), partyId: site.id, lines: [VoucherLine(b, 40)]));
    expect(await r.balance(b.id!, warehouseId: w2.id), 60);
    expect((await r.voucher(out)).total, 200); // 40 @ 5
  });

  test('transfer moves stock and value between warehouses, and deleting it reverts both', () async {
    final jeddah = (await r.warehouses()).firstWhere((w) => w.name == 'مخزن جدة');
    final riyadh = (await r.warehouses()).firstWhere((w) => w.name == 'مخزن الرياض');
    final c = await r.saveItem(const Item(name: 'صنف تحويل'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م-ت'));
    await r.saveVoucher(Voucher(type: VType.inbound, warehouseId: jeddah.id!, date: DateTime(2026, 3, 1), partyId: sup.id, lines: [VoucherLine(c, 100, '', 8)]));

    await r.transfer(fromWh: jeddah.id!, toWh: riyadh.id!, date: DateTime(2026, 3, 2), lines: [MapEntry(c, 30)]);
    expect(await r.balance(c.id!, warehouseId: jeddah.id), 70);
    expect(await r.balance(c.id!, warehouseId: riyadh.id), 30);
    // value followed the goods: Jeddah 70*8=560, Riyadh 30*8=240
    expect((await r.stock(warehouseId: jeddah.id)).firstWhere((x) => x.item.id == c.id).value, 560);
    expect((await r.stock(warehouseId: riyadh.id)).firstWhere((x) => x.item.id == c.id).value, 240);

    // can't transfer more than the source holds
    await expectLater(r.transfer(fromWh: riyadh.id!, toWh: jeddah.id!, date: DateTime(2026, 3, 3), lines: [MapEntry(c, 999)]), throwsA(isA<String>()));
    // same warehouse is refused
    await expectLater(r.transfer(fromWh: jeddah.id!, toWh: jeddah.id!, date: DateTime(2026, 3, 3), lines: [MapEntry(c, 1)]), throwsA(isA<String>()));

    // deleting either side of the transfer removes both and restores balances
    final out = (await r.vouchers(VType.outbound, warehouseId: jeddah.id)).firstWhere((v) => v.isTransfer);
    await r.deleteVoucher(out.id!);
    expect(await r.balance(c.id!, warehouseId: jeddah.id), 100);
    expect(await r.balance(c.id!, warehouseId: riyadh.id), 0);
    expect((await r.vouchers(VType.inbound, warehouseId: riyadh.id)).where((v) => v.isTransfer), isEmpty);
  });

  test('a warehouse with movements cannot be deleted; an empty extra one can', () async {
    final empty = await r.saveWarehouse(const Warehouse(name: 'مخزن فاضي'));
    await r.deleteWarehouse(empty.id!); // fine
    final jeddah = (await r.warehouses()).firstWhere((w) => w.name == 'مخزن جدة');
    await expectLater(r.deleteWarehouse(jeddah.id!), throwsA(isA<String>()));
  });
}
