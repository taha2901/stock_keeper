import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/cubits/voucher_form_cubit.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/backup_service.dart';
import 'package:stock_keeper/services/daily_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp, backups;
  final r = Repo.i;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_safe');
    backups = Directory(p.join(tmp.path, 'bk'));
    AppDb.dir = tmp.path;
    await Directory(AppDb.attachmentsDir).create(recursive: true);
    await Directory(AppDb.backupsDir).create(recursive: true);
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
    await r.setSetting('backup_dir', backups.path);
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  test('a receipt that was issued from cannot be deleted or reduced below what left', () async {
    final a = await r.saveItem(const Item(name: 'صنف1'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'ق'));
    final inId = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 1), partyId: sup.id, refNo: 'INV-1', lines: [VoucherLine(a, 10, '', 5)]));
    final outId = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 1, 2), partyId: site.id, lines: [VoucherLine(a, 8)]));

    await expectLater(r.deleteVoucher(inId), throwsA(isA<String>()));
    expect(await r.balance(a.id!), 2);

    Future<VoucherFormCubit> editWith(double qty) async {
      final f = VoucherFormCubit(VType.inbound, inId);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      f.setQty(f.state.lines.single.uid, qty);
      await f.save();
      return f;
    }

    expect((await editWith(5)).state.error, contains('السالب'));
    expect(await r.balance(a.id!), 2);
    expect((await editWith(8)).state.savedId, isNotNull); // exactly what left is allowed

    await r.deleteVoucher(outId);
    await r.deleteVoucher(inId); // nothing issued any more
  });

  test('duplicate invoice number warns, and saves only when confirmed', () async {
    final a = await r.saveItem(const Item(name: 'صنف2'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م2'));
    await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 2, 1), partyId: sup.id, refNo: 'ABC-9', lines: [VoucherLine(a, 1)]));

    final f = VoucherFormCubit(VType.inbound, null)
      ..setParty(sup)
      ..setRef(' abc-9 ');
    await f.addItem(a);
    f.setQty(f.state.lines.single.uid, 1);
    await f.save();
    expect(f.state.duplicate, contains('متسجل قبل كده'));
    expect(f.state.savedId, isNull);
    await f.save(force: true);
    expect(f.state.savedId, isNotNull);

    // editing a saved receipt doesn't flag itself
    final g = VoucherFormCubit(VType.inbound, f.state.savedId);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    g.setRef('UNIQUE-1');
    await g.save();
    expect(g.state.duplicate, isNull);
    expect(g.state.savedId, isNotNull);
  });

  test('backup includes photos, keeps 14, restores data and repoints photos', () async {
    final photo = File(p.join(AppDb.attachmentsDir, 'inv.jpg'));
    await photo.writeAsBytes([1, 2, 3, 4]);
    final a = await r.saveItem(const Item(name: 'قبل النسخة'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م3'));
    final v = await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 3, 1), partyId: sup.id, attachment: r'C:\old\place\inv.jpg', lines: [VoucherLine(a, 3)]));

    final path = await BackupService.create('manual');
    final bytes = await File(path).readAsBytes();

    await r.saveItem(const Item(name: 'بعد النسخة'));
    await photo.delete();
    await BackupService.restoreBytes(bytes);

    final names = (await r.allItems()).map((i) => i.name);
    expect(names, contains('قبل النسخة'));
    expect(names, isNot(contains('بعد النسخة')));
    expect(await photo.readAsBytes(), [1, 2, 3, 4]);
    expect((await r.voucher(v)).attachment, photo.path);

    await expectLater(BackupService.restoreBytes(Uint8List.fromList([1, 2, 3])), throwsA(isA<String>()));

    for (var i = 0; i < 16; i++) {
      await File(p.join(backups.path, 'stock_backup_2020-01-${(i + 1).toString().padLeft(2, '0')}_00-00-00_auto.zip')).writeAsBytes([0]);
    }
    await BackupService.create('manual');
    final left = await BackupService.list();
    expect(left.length, BackupService.keep);
    expect(left.any((f) => f.path.contains('2020-01-01')), isFalse); // oldest ones removed
    expect(left.any((f) => f.path.contains('2020-01-16')), isTrue);
  });

  test('auto backup runs once a day; stock sheet is due only after its time', () async {
    final before = (await BackupService.list()).length;
    await BackupService.autoBackup();
    await BackupService.autoBackup();
    expect((await BackupService.list()).where((f) => f.path.endsWith('_auto.zip') && !f.path.contains('2020-')).length, 1);
    expect(before, BackupService.keep);

    await r.setSetting('sheet_date', '');
    await r.setSetting('sheet_time', '00:00');
    expect(await DailyService.sheetDue(), isTrue);
    final path = await DailyService.writeSheet();
    expect(await File(path).length(), greaterThan(500));
    expect(await DailyService.sheetDue(), isFalse);
  });

  test('a future or very old date asks first; a normal date does not', () async {
    final a = await r.saveItem(const Item(name: 'تاريخ'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م6'));
    final now = DateTime.now();
    Future<VoucherFormCubit> build(DateTime d) async {
      final f = VoucherFormCubit(VType.inbound, null)..setParty(sup)..setDate(DateTime(d.year, d.month, d.day));
      await f.addItem(a, qty: 1);
      return f;
    }

    final future = await build(now.add(const Duration(days: 3)));
    await future.save();
    expect(future.state.dateWarning, contains('لسه مجاش'));
    expect(future.state.savedId, isNull);
    await future.save(dateOk: true);
    expect(future.state.savedId, isNotNull);

    final old = await build(now.subtract(const Duration(days: 400)));
    await old.save();
    expect(old.state.dateWarning, contains('قديم'));

    final ok = await build(now.subtract(const Duration(days: 5)));
    await ok.save();
    expect(ok.state.dateWarning, isNull);
    expect(ok.state.savedId, isNotNull);

    // editing a saved old voucher without touching its date doesn't nag
    final v = await r.saveVoucher(Voucher(type: VType.inbound, date: now.subtract(const Duration(days: 500)), partyId: sup.id, lines: [VoucherLine(a, 1)]));
    final e = VoucherFormCubit(VType.inbound, v);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    e.setNotes('تعديل');
    await e.save();
    expect(e.state.dateWarning, isNull);
  });

  test('unsaved-changes tracking', () async {
    final a = await r.saveItem(const Item(name: 'تتبع'));
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م7'));
    final start = VoucherFormCubit.unsavedForms;
    final f = VoucherFormCubit(VType.inbound, null);
    expect(f.dirty, isFalse);
    f.setParty(sup);
    expect(f.dirty, isTrue);
    expect(VoucherFormCubit.unsavedForms, start + 1);
    await f.addItem(a, qty: 1);
    await f.save();
    expect(f.dirty, isFalse);
    expect(VoucherFormCubit.unsavedForms, start);
    final g = VoucherFormCubit(VType.inbound, null)..setRef('x');
    await g.close();
    expect(VoucherFormCubit.unsavedForms, start);
  });

  test('backup folder: first usable other disk, else the app folder on C', () async {
    final f = p.join(tmp.path, 'F-drive');
    await Directory(f).create();
    final bad = Directory(r'Q:\').existsSync() ? null : r'Q:\';
    expect(await BackupService.pickFolder([?bad, f]), p.join(f, 'StockKeeperBackups'));
    expect(await BackupService.pickFolder(const []), AppDb.backupsDir);
    expect(await BackupService.pickFolder([?bad]), AppDb.backupsDir);
  });

  test('item price pre-fills a receipt, can be changed there, and FIFO uses the receipt price', () async {
    final a = await r.saveItem(const Item(name: 'سعر افتراضي', price: 100));
    expect((await r.allItems()).firstWhere((i) => i.id == a.id).price, 100);
    final sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'م5'));
    final site = await r.saveParty(const Party(type: PartyType.site, name: 'ق5'));

    final f = VoucherFormCubit(VType.inbound, null)..setParty(sup)..setDate(DateTime(2026, 6, 1));
    await f.addItem(a);
    expect(f.state.lines.single.price, 100);
    f.setQty(f.state.lines.single.uid, 5);
    f.setPrice(f.state.lines.single.uid, 120); // changed while receiving
    await f.save();

    final g = VoucherFormCubit(VType.inbound, null)..setParty(sup)..setDate(DateTime(2026, 6, 2));
    await g.addItem(a);
    g.setQty(g.state.lines.single.uid, 5); // keeps the suggested 100
    await g.save();

    final out = await r.saveVoucher(Voucher(type: VType.outbound, date: DateTime(2026, 6, 3), partyId: site.id, lines: [VoucherLine(a, 7)]));
    expect((await r.voucher(out)).total, 5 * 120 + 2 * 100);

    // changing the item's suggested price later doesn't touch saved receipts
    await r.saveItem(Item(id: a.id, name: 'سعر افتراضي', price: 999));
    expect((await r.voucher(out)).total, 800);
    expect((await r.voucher(f.state.savedId!)).lines.single.item.price, 999);
    expect((await r.voucher(f.state.savedId!)).lines.single.price, 120);
  });
}
