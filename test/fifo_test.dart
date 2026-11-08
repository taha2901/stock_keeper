import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';

void main() {
  late Directory tmp;
  final r = Repo.i;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_fifo');
    AppDb.dir = tmp.path;

    // an existing v1 database with data must upgrade without losing anything
    final old = await databaseFactory.openDatabase(p.join(tmp.path, 'stock.db'),
        options: OpenDatabaseOptions(version: 1, onCreate: (d, _) async {
      await d.execute("CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, name_en TEXT NOT NULL DEFAULT '', code TEXT NOT NULL DEFAULT '', unit TEXT NOT NULL DEFAULT 'قطعة', min_qty REAL NOT NULL DEFAULT 0)");
      await d.execute("CREATE TABLE parties(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, name TEXT NOT NULL COLLATE NOCASE, phone TEXT NOT NULL DEFAULT '', UNIQUE(type, name))");
      await d.execute("CREATE TABLE vouchers(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, number INTEGER NOT NULL, date TEXT NOT NULL, party_id INTEGER, recipient_id INTEGER, ref_no TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', attachment TEXT, created_at TEXT NOT NULL)");
      await d.execute("CREATE TABLE voucher_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, voucher_id INTEGER NOT NULL, item_id INTEGER NOT NULL, qty REAL NOT NULL, note TEXT NOT NULL DEFAULT '')");
      await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await d.insert('items', {'name': 'قديم'});
      await d.insert('vouchers', {'type': 'in', 'number': 1, 'date': '2026-01-01', 'created_at': 'x'});
      await d.insert('voucher_lines', {'voucher_id': 1, 'item_id': 1, 'qty': 5});
    }));
    await old.close();
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  test('old data survives the upgrade and is shown as unpriced', () async {
    final s = (await r.stock()).single;
    expect(s.balance, 5);
    expect(s.value, 0);
    expect(s.missing, isTrue);
  });

  test('FIFO: oldest price is consumed first, across edits and filled-in prices', () async {
    final a = await r.saveItem(const Item(name: 'فلانج'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'سند'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'مكة'));

    // deliberately entered out of order: the later date is saved first
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 2, 1), partyId: sup.id, lines: [VoucherLine(a, 10, '', 30)]));
    final first = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, 10, '', 20)]));
    final out = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 3, 1), partyId: site.id, lines: [VoucherLine(a, 12)]));

    var v = await r.voucher(out);
    expect(v.lines.single.cost.slices.map((s) => (s.qty, s.price)).toList(), [(10.0, 20.0), (2.0, 30.0)]);
    expect(v.total, 260);
    expect(v.missing, isFalse);

    var st = (await r.stock(q: 'فلانج')).single;
    expect(st.balance, 8);
    expect(st.value, 240); // 8 left at 30

    // value in = value out + value left
    final bal = (await r.balanceReport(q: 'فلانج')).single;
    expect([bal.inValue, bal.outValue, bal.closingValue], [500, 260, 240]);

    // period report: opening carries value from before the period
    final mar = (await r.balanceReport(q: 'فلانج', from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31))).single;
    expect([mar.opening, mar.openingValue, mar.outValue, mar.closingValue], [20, 500, 260, 240]);

    // changing an older price flows through to the issue
    await r.saveVoucher(Voucher(id: first, type: VType.inbound, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, 10, '', 25)]));
    v = await r.voucher(out);
    expect(v.total, 310); // 10×25 + 2×30

    // ledger keeps a running stock value
    final led = await r.ledger(a.id!);
    expect(led.map((l) => l.stockValue).toList(), [250, 550, 240]);
  });

  test('missing price: unpriced part is flagged, then completes when filled', () async {
    final b = await r.saveItem(const Item(name: 'ماسورة', unit: 'متر'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'الاتحاد'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'الطائف'));

    final noPrice = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 4, 1), partyId: sup.id, lines: [VoucherLine(b, 10)]));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 4, 2), partyId: sup.id, lines: [VoucherLine(b, 10, '', 7)]));
    final out = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 4, 3), partyId: site.id, lines: [VoucherLine(b, 15)]));

    var v = await r.voucher(out);
    expect(v.total, 35); // only 5 of the 15 have a price
    expect(v.missing, isTrue);
    expect(v.lines.single.cost.unpriced, 10);

    await r.saveVoucher(Voucher(id: noPrice, type: VType.inbound, date: DateTime(2026, 4, 1), partyId: sup.id, lines: [VoucherLine(b, 10, '', 5)]));
    v = await r.voucher(out);
    expect(v.total, 85);
    expect(v.missing, isFalse);
  });

  test('same-day receipt is available to a same-day issue; issue before any receipt is unpriced', () async {
    final c = await r.saveItem(const Item(name: 'جلبة'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'مورد 3'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'موقع 3'));

    final early = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 5, 1), partyId: site.id, lines: [VoucherLine(c, 2)]));
    final sameDayOut = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 5, 2), partyId: site.id, lines: [VoucherLine(c, 1)]));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 5, 2), partyId: sup.id, lines: [VoucherLine(c, 3, '', 4)]));

    expect((await r.voucher(sameDayOut)).total, 4);
    expect((await r.voucher(early)).missing, isTrue);
  });
}
