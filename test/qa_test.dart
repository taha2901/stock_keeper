import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/core/format.dart';
import 'package:stock_keeper/core/theme.dart';
import 'package:stock_keeper/cubits/voucher_form_cubit.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';
import 'package:stock_keeper/services/backup_service.dart';
import 'package:stock_keeper/services/excel_service.dart';
import 'package:stock_keeper/services/pdf_service.dart';
import 'package:stock_keeper/ui/home_page.dart';
import 'package:stock_keeper/ui/item_ledger_page.dart';
import 'package:stock_keeper/ui/parties_page.dart';
import 'package:stock_keeper/ui/reports_page.dart';
import 'package:stock_keeper/ui/settings_page.dart';
import 'package:stock_keeper/ui/shell.dart';
import 'package:stock_keeper/ui/stock_page.dart';
import 'package:stock_keeper/ui/voucher_form_page.dart';
import 'package:stock_keeper/ui/voucher_view_page.dart';
import 'package:stock_keeper/ui/vouchers_page.dart';

const phone = Size(360, 740), desktop = Size(1400, 860);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  final r = Repo.i;
  late Item longItem;
  late Party sup, site, rec;
  late int inId, outId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('stock_qa');
    AppDb.dir = tmp.path;
    await Directory(AppDb.attachmentsDir).create(recursive: true);
    await Directory(AppDb.backupsDir).create(recursive: true);
    await AppDb.open();
    await Repo.i.loadCurrentWarehouse();
    await r.setSetting('backup_dir', p.join(tmp.path, 'bk'));
    final font = FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    await font.load();

    longItem = await r.saveItem(const Item(
        name: 'ماسورة بولي إيثيلين عالية الكثافة قطر 200 مم ضغط 16 بار خطوط زرقاء',
        nameEn: 'OD: 200mm HDPE PIPES SDR11 (Blue Stripes)',
        code: '[P8-4BL-200-16-12]',
        unit: 'متر مكعب',
        minQty: 999999));
    sup = await r.saveParty(const Party(type: PartyType.supplier, name: 'شركة الاتحاد لصناعة الأنابيب المحدودة (Union Pipes Industry Co. LTD)', phone: '0548696607'));
    site = await r.saveParty(const Party(type: PartyType.site, name: 'تنفيذ شبكات توزيع المياه في منطقتي الجوهرة و G24 الطائف'));
    rec = await r.saveParty(const Party(type: PartyType.recipient, name: 'عبدالرحمن محمد عبدالله الشهري'));
    inId = await r.saveVoucher(Voucher(type: VType.inbound, date: today(), partyId: sup.id, refNo: 'WH/OUT/14151-LONG-REFERENCE', notes: 'ملاحظة طويلة جدًا عن هذا السند', lines: [VoucherLine(longItem, 1234567.125, '', 8765.43)]));
    outId = await r.saveVoucher(Voucher(type: VType.outbound, date: today(), partyId: site.id, recipientId: rec.id, lines: [VoucherLine(longItem, 234567.5, 'عاجل')]));
  });
  tearDownAll(() async {
    await AppDb.close();
    await tmp.delete(recursive: true);
  });

  group('numbers', () {
    test('parseNum rejects NaN/Infinity and reads thousands separators', () {
      expect(parseNum('NaN'), isNull);
      expect(parseNum('Infinity'), isNull);
      expect(parseNum('1,000'), 1000);
      expect(parseNum('1,250,000.5'), 1250000.5);
      expect(parseNum('١٬٠٠٠'), 1000);
      expect(parseNum('12,5'), 12.5);
      expect(parseNum('١٢٫٥'), 12.5);
    });

    test('rounding noise is not shown as -0 or as negative stock', () {
      expect(fmtQty(-1e-16), '0');
      expect(const ItemStock(Item(name: 'x'), 0.7, 0.7000000000000001).low, isFalse);
    });

    test('issuing exactly the balance works despite floating point (0.7 + 0.1 = 0.8)', () async {
      final a = await r.saveItem(const Item(name: 'عشري'));
      for (final q in [0.7, 0.1]) {
        await r.saveVoucher(Voucher(type: VType.inbound, date: DateTime(2026, 1, 1), partyId: sup.id, lines: [VoucherLine(a, q)]));
      }
      final f = VoucherFormCubit(VType.outbound, null)..setParty(site);
      await f.addItem(a);
      f.setQty(f.state.lines.single.uid, 0.8);
      await f.save();
      expect(f.state.error, isNull);
      expect(f.state.savedId, isNotNull);
    });

    test('a negative price is refused', () async {
      final a = await r.saveItem(const Item(name: 'سعر سالب'));
      final f = VoucherFormCubit(VType.inbound, null)..setParty(sup);
      await f.addItem(a, qty: 1, price: -5);
      await f.save();
      expect(f.state.savedId, isNull);
      expect(f.state.error, isNotNull);
    });
  });

  test('double-clicking save creates one voucher, not two', () async {
    final a = await r.saveItem(const Item(name: 'ضغط مزدوج'));
    final f = VoucherFormCubit(VType.inbound, null)
      ..setParty(sup)
      ..setRef('DBL-1');
    await f.addItem(a, qty: 1);
    await Future.wait([f.save(), f.save()]);
    expect((await r.vouchers(VType.inbound, q: 'DBL-1')).length, 1);
  });

  group('excel import', () {
    test('matches by exact name / bracket code, never by a loose substring', () async {
      await r.saveItem(const Item(name: 'كود قصير', code: 'P8'));
      final target = await r.saveItem(const Item(name: 'كود كامل', code: 'IFLA160.16'));
      final f = VoucherFormCubit(VType.inbound, null);
      final missing = await f.importRows(const [ImportRow('[P8-4BL-999] OD: 200mm', 1), ImportRow('[IFLA160.16] OD:160mm', 2)]);
      expect(missing.single.name, contains('P8-4BL-999'));
      expect(f.state.lines.single.item.id, target.id);
    });

    test('rows that cannot be read are reported, not silently dropped', () {
      final bytes = ExcelService.table('x', ExcelService.templateHeaders, [
        ['صنف سليم', 3, '', '', null],
        ['كمية غلط', 'تلاتة', '', '', null],
      ]);
      final skipped = <String>[];
      expect(ExcelService.parse(bytes, skipped: skipped).length, 1);
      expect(skipped.single, contains('كمية غلط'));
    });
  });

  group('pdf', () {
    test('a report longer than 20 pages still generates', () async {
      final rows = [for (var i = 0; i < 1500; i++) <Object?>['صنف رقم $i', 'عدد', i.toDouble()]];
      final b = await PdfService.tableBytes('تقرير طويل', '', const ['الصنف', 'الوحدة', 'الكمية'], rows);
      expect(b.length, greaterThan(1000));
    });

    test('symbols real item names use do not break it', () async {
      final b = await PdfService.tableBytes('رموز', '', const ['الصنف', 'x'], const [
        ['ELBOW 45° SDR11 – “FAB” Ø110 × 2', 1],
        ['كوع 45° – قطر Ø110', 2],
        ['م³ / متر²', 3],
      ]);
      await Directory('build/qa').create(recursive: true);
      await File('build/qa/symbols.pdf').writeAsBytes(b);
    });
  });

  test('backup falls back when the chosen folder is unreachable', () async {
    if (Directory(r'Q:\').existsSync()) return;
    final saved = await r.setting('backup_dir');
    await r.setSetting('backup_dir', r'Q:\nope');
    expect(await BackupService.usableFolder(), AppDb.backupsDir);
    await r.setSetting('backup_dir', saved);
  });

  test('performance: 20,000 lines', () async {
    final items = [for (var i = 0; i < 200; i++) await r.saveItem(Item(name: 'حمل $i'))];
    await AppDb.db.transaction((tx) async {
      for (var v = 0; v < 2000; v++) {
        final id = await tx.insert('vouchers', {'type': v.isEven ? 'in' : 'out', 'number': 90000 + v, 'warehouse_id': Repo.i.currentWarehouseId, 'date': dbDate(DateTime(2025, 1, 1).add(Duration(hours: v * 4))), 'party_id': v.isEven ? sup.id : site.id, 'created_at': 'x'});
        for (var l = 0; l < 10; l++) {
          await tx.insert('voucher_lines', {'voucher_id': id, 'item_id': items[(v ~/ 2 + l) % 200].id, 'qty': v.isEven ? 10 : 3, 'price': v.isEven ? 5.5 + v : null});
        }
      }
    });
    Future<int> ms(Future<void> Function() f) async {
      final s = Stopwatch()..start();
      await f();
      return s.elapsedMilliseconds;
    }

    final stock = await ms(() => r.stock());
    final bal = await ms(() => r.balanceReport());
    final mov = await ms(() => r.movements());
    final list = await ms(() => r.vouchers(VType.inbound));
    // ignore: avoid_print
    print('PERF ms: stock=$stock balance=$bal movements=$mov vouchers=$list');
    expect(stock, lessThan(3000));
    await AppDb.db.delete('voucher_lines', where: 'voucher_id IN (SELECT id FROM vouchers WHERE number >= 90000)');
    await AppDb.db.delete('vouchers', where: 'number >= 90000');
  });

  group('screens', () {
    Future<void> show(WidgetTester t, Widget w, Size s) async {
      t.view.physicalSize = s;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: w,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    Future<void> clear(WidgetTester t) async {
      await t.runAsync(() async {
        await t.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }

    final pages = <String, Widget Function()>{
      'home': () => HomePage(onNav: (_) {}),
      'in': () => const VouchersPage(type: VType.inbound),
      'out': () => const VouchersPage(type: VType.outbound),
      'stock': () => const StockPage(),
      'reports': () => const ReportsPage(),
      'parties': () => const PartiesPage(),
      'settings': () => const SettingsPage(),
      'newIn': () => const VoucherFormPage(type: VType.inbound),
      'editIn': () => VoucherFormPage(type: VType.inbound, id: inId),
      'editOut': () => VoucherFormPage(type: VType.outbound, id: outId),
      'viewIn': () => VoucherViewPage(id: inId),
      'viewOut': () => VoucherViewPage(id: outId),
      'ledger': () => ItemLedgerPage(stock: ItemStock(longItem, 0, 0)),
      'shell': () => const Shell(),
    };

    for (final e in pages.entries) {
      for (final size in [phone, desktop]) {
        testWidgets('${e.key} @ ${size.width.toInt()}', (t) async {
          await show(t, e.value(), size);
          expect(t.takeException(), isNull);
          await clear(t);
        });
      }
    }

    testWidgets('report tabs: phone layout has no overflow in any mode', (t) async {
      await show(t, const ReportsPage(), phone);
      for (final tab in ['صادر', 'الرصيد', 'وارد']) {
        await t.runAsync(() async {
          await t.tap(find.text(tab).first);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await t.pump();
        expect(t.takeException(), isNull, reason: tab);
      }
      await clear(t);
    });

    testWidgets('leaving a form with changes asks first; without changes it just leaves', (t) async {
      await show(t, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const VoucherFormPage(type: VType.inbound))), child: const Text('open')))), desktop);
      Future<void> settle(Future<void> Function() f) async {
        await t.runAsync(() async {
          await f();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      }

      await settle(() => t.tap(find.text('open')));
      await settle(() => t.tap(find.byType(BackButton)));
      expect(find.text('open'), findsOneWidget); // clean form leaves at once
      expect(find.text('خروج من غير حفظ'), findsNothing);

      await settle(() => t.tap(find.text('open')));
      await settle(() => t.enterText(find.widgetWithText(TextFormField, 'ملاحظات'), 'كتبت حاجة'));
      await settle(() => t.tap(find.byType(BackButton)));
      expect(find.text('خروج من غير حفظ'), findsOneWidget);
      await settle(() => t.tap(find.text('إلغاء')));
      expect(find.widgetWithText(TextFormField, 'ملاحظات'), findsOneWidget); // stayed, text kept
      await settle(() => t.tap(find.byType(BackButton)));
      await settle(() => t.tap(find.text('اخرج')));
      expect(find.text('open'), findsOneWidget);
      await clear(t);
    });

    testWidgets('report search text stays when switching tabs', (t) async {
      await show(t, const ReportsPage(), desktop);
      final field = find.widgetWithText(TextField, 'بحث بالصنف...');
      await t.runAsync(() async {
        await t.enterText(field, 'ماسورة');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('صادر').first);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(find.text('ماسورة'), findsOneWidget);
      await clear(t);
    });
  });
}
