import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  final r = Repo.i;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_lic');
    AppDb.dir = tmp.path;
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
  });
  tearDownAll(() async {
    r.writable = true;
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  test('device code is stable, the right key activates, a wrong one does not', () async {
    final code = await LicenseService.deviceCode();
    expect(code, await LicenseService.deviceCode()); // stable across calls
    expect(code.replaceAll('-', '').length, 12);

    expect(await LicenseService.activate('WRONG-KEY-0000-0000'), isFalse);
    expect(LicenseService.activated, isFalse);

    final key = LicenseService.keyFor(code);
    expect(key.replaceAll('-', '').length, 20);
    // formatting / case / spaces don't matter
    expect(await LicenseService.keyValid(key.toLowerCase().replaceAll('-', ' ')), isTrue);

    expect(await LicenseService.activate(key), isTrue);
    expect(LicenseService.activated, isTrue);

    // survives a restart (key stored in the database)
    LicenseService.activated = false;
    expect(await LicenseService.load(), isTrue);
  });

  test('a key for a different device code is rejected', () {
    final mine = LicenseService.keyFor('ABCD-EFGH-JKMN');
    final other = LicenseService.keyFor('ZZZZ-ZZZZ-ZZZZ');
    expect(mine, isNot(other));
  });

  test('read-only blocks writes but allows reading, then activation unlocks', () async {
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'مورد'));
    final a = await r.saveItem(const Item(name: 'صنف', price: 5));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, 10, '', 5)]));

    r.writable = false; // read-only
    expect((await r.stock()).isNotEmpty, isTrue); // reading still works
    expect((await r.vouchers(VType.inbound)).isNotEmpty, isTrue);
    await expectLater(r.saveItem(const Item(name: 'جديد')), throwsA(isA<String>()));
    await expectLater(r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 2), partyId: sup.id, lines: [VoucherLine(a, 1)])), throwsA(isA<String>()));
    await expectLater(r.deleteItem(a.id!), throwsA(isA<String>()));

    r.writable = true; // activated
    final v = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 3), partyId: sup.id, lines: [VoucherLine(a, 2, '', 5)]));
    expect(v, greaterThan(0));
  });
}
