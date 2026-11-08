import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';

/// Transfers between warehouses, valued with FIFO across several purchase prices.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final r = Repo.i;
  late Directory tmp;
  late Warehouse a, b, c;
  late Party sup, site;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_tr');
    AppDb.dir = tmp.path;
    await AppDb.open();
    await r.loadCurrentWarehouse();
    a = (await r.warehouses()).single;
    b = await r.saveWarehouse(const Warehouse(name: 'مخزن ب'));
    c = await r.saveWarehouse(const Warehouse(name: 'مخزن ج'));
    sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'الاتحاد'));
    site = await r.saveParty(const Party(type: PartyType.site, name: 'الطائف'));
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  DateTime d(int day) => DateTime(2026, 1, day);
  Future<int> receive(Warehouse w, Item it, double q, double? price, int day) =>
      r.saveVoucher(Voucher(type: VType.inbound, warehouseId: w.id!, date: d(day), partyId: sup.id, lines: [VoucherLine(it, q, '', price)]));
  Future<int> issue(Warehouse w, Item it, double q, int day) =>
      r.saveVoucher(Voucher(type: VType.outbound, warehouseId: w.id!, date: d(day), partyId: site.id, lines: [VoucherLine(it, q)]));
  Future<ItemStock> st(Warehouse w, Item it) async => (await r.stock(warehouseId: w.id, includeEmpty: true)).firstWhere((s) => s.item.id == it.id);
  List<(double, double?)> layers(LineCost c) => [for (final s in c.slices) (s.qty, s.price)];
  Future<Voucher> lastTransfer(Warehouse w, VType t) async => (await r.vouchers(t, warehouseId: w.id)).firstWhere((v) => v.isTransfer);

  test('two purchase prices: the transfer carries the exact FIFO layers, value is preserved', () async {
    final it = await r.saveItem(const Item(name: 'جلبة 110'));
    await receive(a, it, 10, 20, 1);
    await receive(a, it, 10, 30, 5);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(10), lines: [MapEntry(it, 15)]);

    final outV = await r.voucher((await lastTransfer(a, VType.outbound)).id!);
    final inV = await r.voucher((await lastTransfer(b, VType.inbound)).id!);
    expect(layers(outV.lines.single.cost), [(10.0, 20.0), (5.0, 30.0)]);
    expect(layers(inV.lines.single.cost), [(10.0, 20.0), (5.0, 30.0)]); // not an average
    expect(outV.total, 350);
    expect(inV.total, 350);

    expect((await st(a, it)).balance, 5);
    expect((await st(a, it)).value, 150); // 5 @ 30 left
    expect((await st(b, it)).balance, 15);
    expect((await st(b, it)).value, 350);
    expect((await st(a, it)).value + (await st(b, it)).value, 500); // nothing created or lost

    // the destination issues FIFO from what it received: oldest price first
    final o = await issue(b, it, 12, 11);
    expect(layers((await r.voucher(o)).lines.single.cost), [(10.0, 20.0), (2.0, 30.0)]);
    expect((await r.voucher(o)).total, 260);
    expect((await st(b, it)).value, 90); // 3 @ 30

    // correcting the first purchase price flows through the transfer to the destination's issue
    final first = (await r.vouchers(VType.inbound, warehouseId: a.id)).firstWhere((v) => v.date == d(1));
    await r.saveVoucher(Voucher(id: first.id, type: VType.inbound, warehouseId: a.id!, date: d(1), partyId: sup.id, lines: [VoucherLine(it, 10, '', 25)]));
    expect((await r.voucher(inV.id!)).total, 400); // 10×25 + 5×30
    expect((await r.voucher(o)).total, 310); // 10×25 + 2×30
    expect((await st(b, it)).value, 90);
    expect((await st(a, it)).value, 150);
    // received 10×25 + 10×30 = 550 = issued 310 + left 150 + 90
    expect(310 + 150 + 90, 550);
  });

  test('unpriced stock transfers unpriced, then gets priced when the receipt price is filled in', () async {
    final it = await r.saveItem(const Item(name: 'محبس 100'));
    final rec = await receive(a, it, 8, null, 1);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(2), lines: [MapEntry(it, 5)]);
    var inV = await r.voucher((await r.vouchers(VType.inbound, warehouseId: b.id, q: 'محبس 100')).single.id!);
    expect(inV.missing, isTrue);
    expect((await st(b, it)).missing, isTrue);

    await r.saveVoucher(Voucher(id: rec, type: VType.inbound, warehouseId: a.id!, date: d(1), partyId: sup.id, lines: [VoucherLine(it, 8, '', 90)]));
    inV = await r.voucher(inV.id!);
    expect(inV.missing, isFalse);
    expect(inV.total, 450);
    expect((await st(b, it)).value, 450);
    expect((await st(a, it)).value, 270);
  });

  test('a transfer can\'t take stock that only arrives later, or that a later issue needs', () async {
    final it = await r.saveItem(const Item(name: 'كوع 45'));
    await receive(a, it, 10, 5, 10);
    // dated before the receipt: the source had nothing that day
    await expectLater(r.transfer(fromWh: a.id!, toWh: b.id!, date: d(5), lines: [MapEntry(it, 4)]),
        throwsA(allOf(isA<String>(), contains('تاريخ'))));
    // a later issue already used 8 of the 10: only 2 can move on day 12
    await issue(a, it, 8, 20);
    await expectLater(r.transfer(fromWh: a.id!, toWh: b.id!, date: d(12), lines: [MapEntry(it, 3)]), throwsA(isA<String>()));
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(12), lines: [MapEntry(it, 2)]);
    expect((await st(a, it)).balance, 0);
    expect((await st(a, it)).value, 0);
    expect((await st(b, it)).value, 10);
    // more than the total is refused with the plain message
    await expectLater(r.transfer(fromWh: b.id!, toWh: a.id!, date: d(21), lines: [MapEntry(it, 99)]), throwsA(isA<String>()));
    // nothing half-saved after a refusal
    expect((await r.vouchers(VType.outbound, warehouseId: b.id, q: 'كوع 45')), isEmpty);
  });

  test('chain A -> B -> C on the same day, and back: value follows the goods', () async {
    final it = await r.saveItem(const Item(name: 'مسلوب'));
    await receive(a, it, 4, 10, 1);
    await receive(a, it, 6, 40, 2);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(3), lines: [MapEntry(it, 7)]); // 4@10 + 3@40
    await r.transfer(fromWh: b.id!, toWh: c.id!, date: d(3), lines: [MapEntry(it, 5)]); // 4@10 + 1@40
    expect(layers((await r.balanceReport(warehouseId: c.id)).firstWhere((x) => x.item.id == it.id).left), [(4.0, 10.0), (1.0, 40.0)]);
    expect((await st(b, it)).value, 80); // 2 @ 40
    expect((await st(c, it)).value, 80);
    // send it back to A: A now holds 3@40 (own) + the returned 4@10 + 1@40
    await r.transfer(fromWh: c.id!, toWh: a.id!, date: d(4), lines: [MapEntry(it, 5)]);
    expect((await st(c, it)).balance, 0);
    expect((await st(a, it)).balance, 8);
    expect((await st(a, it)).value, 3 * 40 + 4 * 10 + 1 * 40);
    final total = (await st(a, it)).value + (await st(b, it)).value + (await st(c, it)).value;
    expect(total, 4 * 10 + 6 * 40);
  });

  test('the same item twice in one transfer becomes one line', () async {
    final it = await r.saveItem(const Item(name: 'طبة'));
    await receive(a, it, 10, 3, 1);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(2), lines: [MapEntry(it, 2), MapEntry(it, 3)]);
    final out = await r.voucher((await r.vouchers(VType.outbound, warehouseId: a.id, q: 'طبة')).single.id!);
    expect(out.lines.single.qty, 5);
    expect((await st(b, it)).balance, 5);
    await expectLater(r.transfer(fromWh: a.id!, toWh: b.id!, date: d(2), lines: [MapEntry(it, 0)]), throwsA(isA<String>()));
  });

  test('a transfer can\'t be edited, only deleted (both sides together)', () async {
    final it = await r.saveItem(const Item(name: 'رينج'));
    await receive(a, it, 10, 7, 1);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(2), lines: [MapEntry(it, 4)]);
    final inV = await r.voucher((await r.vouchers(VType.inbound, warehouseId: b.id, q: 'رينج')).single.id!);
    await expectLater(
        r.saveVoucher(Voucher(id: inV.id, type: VType.inbound, warehouseId: b.id!, date: d(2), lines: [VoucherLine(it, 9, '', 1)])), throwsA(isA<String>()));
    expect((await st(b, it)).balance, 4); // unchanged

    // goods already issued at the destination: deleting the transfer would make it negative
    final o = await issue(b, it, 3, 3);
    await expectLater(r.deleteVoucher(inV.id!), throwsA(isA<String>()));
    await r.deleteVoucher(o);
    await r.deleteVoucher(inV.id!);
    expect((await st(a, it)).balance, 10);
    expect((await st(a, it)).value, 70);
    expect((await st(b, it)).balance, 0);
    expect((await r.vouchers(VType.outbound, warehouseId: a.id, q: 'رينج')), isEmpty);
  });

  test('the source receipt can\'t be deleted or cut below what was transferred', () async {
    final it = await r.saveItem(const Item(name: 'مواسير 160'));
    final rec = await receive(a, it, 100, 39.08, 1);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(2), lines: [MapEntry(it, 60)]);
    await expectLater(r.deleteVoucher(rec), throwsA(isA<String>()));
    expect(await r.receiptConflicts(await r.voucher(rec), {it.id!: 50}), isNotEmpty);
    expect(await r.receiptConflicts(await r.voucher(rec), {it.id!: 60}), isEmpty);
  });

  test('balance report per warehouse: opening + in - out = closing, by name and price', () async {
    final it = await r.saveItem(const Item(name: 'OD:160mm HDPE EF COUPLER SDR11 [ACUP160.16]', code: 'ACUP160.16'));
    await receive(a, it, 10, 20, 1);
    await receive(a, it, 10, 30, 15);
    await issue(a, it, 4, 16);
    await r.transfer(fromWh: a.id!, toWh: b.id!, date: d(17), lines: [MapEntry(it, 10)]);

    // period 10..20 in A: opening 10@20; in 10@30; out 4@20 (site) + 10 (6@20 + 4@30, transfer)
    final row = (await r.balanceReport(warehouseId: a.id, from: d(10), to: d(20))).firstWhere((x) => x.item.id == it.id);
    expect([row.opening, row.inQty, row.outQty, row.closing], [10, 10, 14, 6]);
    expect([row.openingValue, row.inValue, row.outValue, row.closingValue], [200, 300, 80 + 120 + 120, 180]);
    expect(layers(row.left), [(6.0, 30.0)]);
    expect(row.closingValue, row.left.value);
    expect(row.ins.single.party, 'الاتحاد');
    expect(row.ins.single.cost.slices.single.price, 30);
    expect(row.outs.map((m) => m.who), ['الطائف', 'تحويل إلى: مخزن ب']);
    expect(row.outs.last.isTransfer, isTrue);
    expect(row.item.title, 'جلبة EF قطر 160مم'); // shown in Arabic

    // B sees the transfer as its receipt, priced with A's layers
    final rb = (await r.balanceReport(warehouseId: b.id, from: d(10), to: d(20))).firstWhere((x) => x.item.id == it.id);
    expect(rb.ins.single.who, 'تحويل من: المخزن الرئيسي');
    expect(layers(rb.ins.single.cost), [(6.0, 20.0), (4.0, 30.0)]);
    expect(rb.closingValue, 240);

    // a period that ends before the second receipt doesn't see it
    final early = (await r.balanceReport(warehouseId: a.id, to: d(10))).firstWhere((x) => x.item.id == it.id);
    expect([early.closing, early.closingValue], [10, 200]);
    // nothing before or inside the period: the item isn't listed
    expect((await r.balanceReport(warehouseId: b.id, to: d(5))).where((x) => x.item.id == it.id), isEmpty);
  });

  test('stress: random receipts, issues, transfers, price fixes and deletes keep the books balanced', () async {
    final rnd = Random(2026);
    final whs = [a, b, c];
    final items = [for (var i = 0; i < 4; i++) await r.saveItem(Item(name: 'صنف عشوائي $i'))];
    final ids = items.map((i) => i.id).toSet();
    final receipts = <int>[];
    final transfers = <int>[];

    Future<void> check(String step) async {
      final f = await r.fifo();
      // 1) per warehouse: the layers left equal the real balance
      for (final w in whs) {
        for (final it in items) {
          final bal = await r.balance(it.id!, warehouseId: w.id);
          final left = f.remaining[(w.id!, it.id!)] ?? LineCost.none;
          final q = left.slices.fold(0.0, (x, s) => x + s.qty);
          expect(bal, greaterThanOrEqualTo(-1e-9), reason: '$step: negative balance');
          expect(q, closeTo(bal, 1e-6), reason: '$step: layers ${layers(left)} vs balance $bal in ${w.name}');
        }
      }
      // 2) every transfer receipt carries exactly what its issue took
      final lines = await AppDb.db.rawQuery('''
        SELECT l.id, l.item_id, v.type, v.transfer_id AS tid, l.qty, l.price FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id
        WHERE l.item_id IN (${ids.join(',')})''');
      final outs = {for (final l in lines.where((l) => l['tid'] != null && l['type'] == 'out')) (l['tid'], l['item_id']): l['id'] as int};
      for (final l in lines.where((l) => l['tid'] != null && l['type'] == 'in')) {
        expect(layers(f.costs[l['id']]!), layers(f.costs[outs[(l['tid'], l['item_id'])]]!), reason: '$step: transfer value differs');
      }
      // 3) value received from suppliers = value issued to sites + value left (transfers net to zero)
      var inV = 0.0, outV = 0.0, inQ = 0.0, outQ = 0.0;
      for (final l in lines.where((l) => l['tid'] == null)) {
        final cost = f.costs[l['id']]!;
        if (l['type'] == 'in') {
          inV += cost.value;
          inQ += (l['qty'] as num).toDouble();
        } else {
          outV += cost.value;
          outQ += (l['qty'] as num).toDouble();
        }
      }
      var leftV = 0.0, leftQ = 0.0;
      for (final w in whs) {
        for (final it in items) {
          final left = f.remaining[(w.id!, it.id!)] ?? LineCost.none;
          leftV += left.value;
          leftQ += left.slices.fold(0.0, (x, s) => x + s.qty);
        }
      }
      expect(inQ, closeTo(outQ + leftQ, 1e-6), reason: '$step: quantity');
      expect(inV, closeTo(outV + leftV, 1e-6), reason: '$step: value');
      // 4) the balance report agrees with the stock screen and with its own layers
      for (final w in whs) {
        for (final row in (await r.balanceReport(warehouseId: w.id)).where((x) => ids.contains(x.item.id))) {
          final s = await st(w, row.item);
          expect(row.closing, closeTo(s.balance, 1e-6), reason: step);
          expect(row.closingValue, closeTo(s.value, 1e-6), reason: '$step: report value ${w.name}');
          expect(row.closingValue, closeTo(row.left.value, 1e-6), reason: step);
        }
      }
    }

    for (var step = 0; step < 160; step++) {
      final w = whs[rnd.nextInt(3)];
      final it = items[rnd.nextInt(items.length)];
      final day = 1 + rnd.nextInt(28);
      final op = rnd.nextInt(10);
      final label = 'step $step op $op';
      if (op < 4) {
        final price = rnd.nextInt(6) == 0 ? null : (5 + rnd.nextInt(40)).toDouble();
        receipts.add(await receive(w, it, (1 + rnd.nextInt(20)).toDouble(), price, day));
      } else if (op < 6) {
        // like the voucher form: only checks the total balance, so backdated issues happen
        final bal = await r.balance(it.id!, warehouseId: w.id);
        if (bal >= 1) await issue(w, it, (1 + rnd.nextInt(bal.floor())).toDouble(), day);
      } else if (op < 8) {
        final to = whs.where((x) => x.id != w.id).toList()[rnd.nextInt(2)];
        final avail = await r.availableOn(it.id!, w.id!, d(day));
        if (avail >= 1) {
          await r.transfer(fromWh: w.id!, toWh: to.id!, date: d(day), lines: [MapEntry(it, (1 + rnd.nextInt(avail.floor())).toDouble())]);
          transfers.add((await AppDb.db.rawQuery("SELECT MAX(id) AS m FROM vouchers WHERE type = 'out' AND transfer_id IS NOT NULL")).first['m'] as int);
        } else {
          await expectLater(r.transfer(fromWh: w.id!, toWh: to.id!, date: d(day), lines: [MapEntry(it, avail.floor() + 1.0)]), throwsA(isA<String>()));
        }
      } else if (op == 8 && receipts.isNotEmpty) {
        // fix a receipt's price (or fill a missing one)
        final id = receipts[rnd.nextInt(receipts.length)];
        final v = await r.voucher(id);
        await r.saveVoucher(Voucher(
            id: id, type: VType.inbound, warehouseId: v.warehouseId, date: v.date, partyId: v.partyId,
            lines: [for (final l in v.lines) VoucherLine(l.item, l.qty, '', (5 + rnd.nextInt(40)).toDouble())]));
      } else if (op == 9) {
        // delete a transfer or a receipt; refused when stock was already used
        final pool = rnd.nextBool() ? transfers : receipts;
        if (pool.isNotEmpty) {
          final id = pool[rnd.nextInt(pool.length)];
          try {
            await r.deleteVoucher(id);
            pool.remove(id);
          } catch (e) {
            expect(e, isA<String>());
          }
        }
      }
      await check(label);
    }
    // the run really exercised transfers, issues, and issues dated before their receipt
    final n = await AppDb.db.rawQuery('''
      SELECT SUM(v.transfer_id IS NOT NULL AND v.type = 'out') AS t, SUM(v.transfer_id IS NULL AND v.type = 'out') AS o
      FROM vouchers v JOIN voucher_lines l ON l.voucher_id = v.id WHERE l.item_id IN (${ids.join(',')})''');
    expect(n.first['t'] as int, greaterThan(10));
    expect(n.first['o'] as int, greaterThan(10));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
