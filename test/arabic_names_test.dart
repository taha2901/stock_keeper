import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_keeper/core/db.dart';
import 'package:stock_keeper/cubits/voucher_form_cubit.dart';
import 'package:stock_keeper/data/arabic_names.dart';
import 'package:stock_keeper/data/models.dart';
import 'package:stock_keeper/data/repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('English -> Arabic (wording of «الوارد - المنفذ»)', () {
    // real names from the system, and the row of the sheet they belong to
    const cases = {
      'OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]': 'جلبة EF قطر 110مم',
      'OD:160mm HDPE EF COUPLER SDR11 [ACUP160.16]': 'جلبة EF قطر 160مم',
      'OD:200mm HDPE EF COUPLER SDR11 [ACUP200.16]': 'جلبة EF قطر 200مم',
      'OD:200mm HDPE EF ELBOW 45° SDR11 [AELBEF200-45.16]': 'كوع 45 قطر 200مم',
      'OD:160mm HDPE EF ELBOW 45° SDR11 [AELBEF160-45.16]': 'كوع 45 قطر 160مم',
      'OD:200mm HDPE BF ELBOW 11.25° SDR11 FAB [FELB200-11.25.16]': 'كوع 11.25 قطر 200مم',
      'OD:160-110mm HDPE EF REDUCER SDR11 [AREDEF160-110.16]': 'مسلوب قطر 160x110 مم',
      'OD:160-110mm HDPE EF REDUCER TEE SDR11 [ARTEF160-110.16]': 'تي قطر 160x160x110 مم',
      'OD:200-110mm HDPE EF REDUCER TEE SDR11 [ARTEF200-110.16]': 'تي قطر 200x200x110 مم',
      'OD:200-160mm HDPE EF REDUCER TEE SDR11 [ARTEF200-160.16]': 'تي قطر 200x200x160 مم',
      'TEE DIM 110*110*110mm': 'تي قطر 110x110x110 مم',
      'T HDPE 110MM': 'تي قطر 110x110x110 مم',
      'Reducer DIM 200*160 mm': 'مسلوب قطر 200x160 مم',
      'END CAP DIM 110mm': 'طبة نهاية قطر 110مم',
      'OD:110mm PP COATED STEEL FLANGE PN16 [ASF110.16.PPC]': 'رينج 110مم',
      'OD:160mm PP COATED STEEL FLANGE PN16 [ISF160.16.PPC]': 'رينج 160مم',
      'OD:160mm HDPE BF FLANGE ADAPTOR SDR11 INJ [IFLA160.16]': 'فلانشة 160مم',
      'OD:110mm HDPE BF FLANGE ADAPTOR SDR11 INJ [IFLA110.16]': 'فلانشة 110مم',
      'OD: 160mm HDPE PIPES SDR11 (Blue Stripes) [P8-4BL-160-16-12]': 'مواسير قطر 160مم',
      'OD: 110mm HDPE PIPES SDR11 (Blue Stripes) [P8-4BL-110-16-12]': 'مواسير قطر 110مم',
      'GATE VALVE DN150 PN16': 'محبس قطر 150مم',
      'RESILIENT SEATED GATE VALVE DN100': 'محبس قطر 100مم',
      'FIRE HYDRANT DN100': 'طفايات حريق',
      'BOLT NUT & WASHER 16X100 (SS316)': 'مجموعة مسامير 100مم',
      'BOLT NUT & WASHER 24X150 (SS316)': 'مجموعة مسامير 150مم',
      'ELECTRIC TAPE': 'شريط كهرباء',
      'ELECTRICAL SOCKET': 'فيشة كهرباء',
      'EXTENSION SPINDLE 1000MM FOR GATE VALVE DN250': 'عمود تطويل لمحبس قطر 250مم - طول 1000 مم',
      'EXTENSION SPINDLE LENGTH 100CM FOR 100MM GATE VALVE': 'عمود تطويل لمحبس قطر 100مم - طول 100 سم',
      'EXTENSION SPINDLE LENGTH 100CM FOR 200MM GATE VALVE': 'عمود تطويل لمحبس قطر 200مم - طول 100 سم',
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(ArabicNames.suggest(e.key), e.value));
    }

    test('a spindle is never mistaken for the valve it fits', () {
      expect(ArabicNames.suggest('EXTENSION SPINDLE LENGTH 100CM FOR 150MM GATE VALVE'), isNot(startsWith('محبس')));
    });

    test('unknown or already-Arabic names get no suggestion', () {
      expect(ArabicNames.suggest('SOMETHING UNKNOWN XYZ'), '');
      expect(ArabicNames.suggest('فلانج ادابتور 160 مم'), '');
      expect(ArabicNames.suggest(''), '');
    });
  });

  group('no two items ever share an Arabic name', () {
    test('items with the same base get the detail that differs', () {
      final r = ArabicNames.uniqueAll([
        (id: 1, name: 'OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]', code: 'ACUP110.16'),
        (id: 2, name: 'OD:110mm HDPE EF COUPLER SDR17 [ACUP110.10]', code: 'ACUP110.10'),
        (id: 3, name: 'TEE DIM 110*110*110mm EF', code: ''),
        (id: 4, name: 'T HDPE 110MM', code: ''),
        (id: 5, name: 'OD:160mm HDPE EF COUPLER SDR11 [ACUP160.16]', code: 'ACUP160.16'),
      ]);
      expect(r[1], 'جلبة EF قطر 110مم SDR11');
      expect(r[2], 'جلبة EF قطر 110مم SDR17');
      expect(r[3], 'تي قطر 110x110x110 مم EF');
      expect(r[4], 'تي قطر 110x110x110 مم');
      expect(r[5], 'جلبة EF قطر 160مم'); // alone: stays short
      expect(r.values.toSet().length, r.length);
    });

    test('identical descriptions fall back to the supplier code', () {
      final r = ArabicNames.uniqueAll([
        (id: 1, name: 'OD:110mm HDPE EF COUPLER SDR11 [A1]', code: 'A1'),
        (id: 2, name: 'OD:110mm HDPE EF COUPLER SDR11 [B2]', code: 'B2'),
      ]);
      expect(r[1], 'جلبة EF قطر 110مم (A1)');
      expect(r[2], 'جلبة EF قطر 110مم (B2)');
    });

    test('a name already used by another item is not reused', () {
      final r = ArabicNames.uniqueAll([(id: 1, name: 'ELECTRIC TAPE', code: '')], taken: {'شريط كهرباء'});
      expect(r[1], isNot('شريط كهرباء'));
      expect(r[1], startsWith('شريط كهرباء'));
    });
  });

  group('database', () {
    late Directory tmp;
    final r = Repo.i;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmp = await Directory.systemTemp.createTemp('stock_ar');
      AppDb.dir = tmp.path;
      // a v5 database exactly as the keeper has it today: English names only
      final old = await databaseFactory.openDatabase(p.join(tmp.path, 'stock.db'),
          options: OpenDatabaseOptions(version: 5, onCreate: (d, _) async {
        await d.execute('CREATE TABLE warehouses(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, created_at TEXT NOT NULL)');
        await d.insert('warehouses', {'name': 'المخزن الرئيسي / المواد', 'created_at': 'x'});
        await d.execute("CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, name_en TEXT NOT NULL DEFAULT '', code TEXT NOT NULL DEFAULT '', unit TEXT NOT NULL DEFAULT 'قطعة', min_qty REAL NOT NULL DEFAULT 0, price REAL)");
        await d.execute("CREATE TABLE parties(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, name TEXT NOT NULL COLLATE NOCASE, phone TEXT NOT NULL DEFAULT '', UNIQUE(type, name))");
        await d.execute("CREATE TABLE vouchers(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, number INTEGER NOT NULL, date TEXT NOT NULL, warehouse_id INTEGER NOT NULL, party_id INTEGER, recipient_id INTEGER, ref_no TEXT NOT NULL DEFAULT '', license_no TEXT NOT NULL DEFAULT '', transfer_id INTEGER, notes TEXT NOT NULL DEFAULT '', attachment TEXT, created_at TEXT NOT NULL)");
        await d.execute("CREATE TABLE voucher_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, voucher_id INTEGER NOT NULL, item_id INTEGER NOT NULL, qty REAL NOT NULL, note TEXT NOT NULL DEFAULT '', price REAL)");
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        for (final n in [
          ('OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]', 'ACUP110.16'),
          ('OD:160mm HDPE EF COUPLER SDR11 [ACUP160.16]', 'ACUP160.16'),
          ('OD:160mm PP COATED STEEL FLANGE PN16 [ISF160.16.PPC]', 'ISF160.16.PPC'),
          ('OD:160mm HDPE BF FLANGE ADAPTOR SDR11 INJ [IFLA160.16]', 'IFLA160.16'),
          ('SOMETHING UNKNOWN', ''),
          ('فلانج قديم 90 مم', ''),
        ]) {
          await d.insert('items', {'name': n.$1, 'code': n.$2, 'unit': 'عدد'});
        }
        await d.insert('vouchers', {'type': 'in', 'number': 1, 'date': '2026-10-27', 'warehouse_id': 1, 'created_at': 'x'});
        await d.insert('voucher_lines', {'voucher_id': 1, 'item_id': 1, 'qty': 30, 'price': 20.16});
      }));
      await old.close();
      await AppDb.open();
      await r.loadCurrentWarehouse();
      await r.loadNameMode();
    });
    tearDownAll(() async {
      Item.mode = NameMode.both;
      await AppDb.close();
      await tmp.delete(recursive: true);
    });

    test('upgrade fills Arabic names once, keeps the original names and the stock untouched', () async {
      final all = {for (final i in await r.allItems()) i.code.isEmpty ? i.name : i.code: i};
      expect(all['ACUP110.16']!.nameAr, 'جلبة EF قطر 110مم');
      expect(all['ACUP110.16']!.name, 'OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]');
      expect(all['ISF160.16.PPC']!.nameAr, 'رينج 160مم');
      expect(all['IFLA160.16']!.nameAr, 'فلانشة 160مم');
      expect(all['SOMETHING UNKNOWN']!.nameAr, ''); // left for the keeper
      expect(all['فلانج قديم 90 مم']!.nameAr, ''); // already Arabic
      expect((await r.stock()).single.balance, 30);
      expect((await r.stock()).single.value, closeTo(604.8, 1e-9));
      expect(Item.mode, NameMode.both); // default after the update
    });

    test('display follows the chosen mode everywhere', () async {
      final it = (await r.allItems()).firstWhere((i) => i.code == 'ACUP110.16');
      Item.mode = NameMode.both;
      expect(it.title, 'جلبة EF قطر 110مم');
      expect(it.extra, contains('OD:110mm HDPE EF COUPLER'));
      expect(it.label, 'جلبة EF قطر 110مم\nOD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]');
      Item.mode = NameMode.ar;
      expect(it.title, 'جلبة EF قطر 110مم');
      expect(it.extra, 'ACUP110.16');
      expect(it.label, 'جلبة EF قطر 110مم');
      Item.mode = NameMode.en;
      expect(it.title, 'OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]');
      expect(it.label, it.name);
      final unknown = (await r.allItems()).firstWhere((i) => i.name == 'SOMETHING UNKNOWN');
      Item.mode = NameMode.ar;
      expect(unknown.title, 'SOMETHING UNKNOWN'); // no Arabic yet: the original is shown, never blank
      await r.setNameMode(NameMode.ar);
      await r.loadNameMode();
      expect(Item.mode, NameMode.ar);
      await r.setNameMode(NameMode.both);
    });

    test('search finds items by the Arabic name', () async {
      final s = await r.stock(q: 'جلبة', includeEmpty: true);
      expect(s.map((x) => x.item.code), containsAll(['ACUP110.16', 'ACUP160.16']));
      expect((await r.movements(q: 'جلبة EF قطر 110')).length, 1);
    });

    test('saving names refuses two items with the same name, and keeps the old ones', () async {
      final all = await r.allItems();
      final a = all.firstWhere((i) => i.code == 'ACUP110.16'), b = all.firstWhere((i) => i.code == 'ACUP160.16');
      await expectLater(r.saveArabicNames({b.id!: 'جلبة EF قطر 110مم'}), throwsA(isA<String>()));
      expect((await r.allItems()).firstWhere((i) => i.id == b.id).nameAr, 'جلبة EF قطر 160مم');
      // an Arabic name equal to another item's original Arabic name is refused too
      await expectLater(r.saveArabicNames({a.id!: 'فلانج قديم 90 مم'}), throwsA(isA<String>()));
      // a valid rename works
      await r.saveArabicNames({a.id!: 'جلبة كهرباء 110'});
      expect((await r.allItems()).firstWhere((i) => i.id == a.id).nameAr, 'جلبة كهرباء 110');
      await r.saveArabicNames({a.id!: 'جلبة EF قطر 110مم'});
    });

    test('a new English item gets a unique Arabic name; the item dialog check stops clashes', () async {
      final n = await r.saveItem(const Item(name: 'OD:110mm HDPE EF COUPLER SDR17 [ACUP110.10]', code: 'ACUP110.10'));
      expect(n.nameAr, isNotEmpty);
      expect(n.nameAr, isNot('جلبة EF قطر 110مم'));
      final e = (await r.allItems()).firstWhere((i) => i.id == n.id);
      expect(e.nameAr, n.nameAr);
      await expectLater(r.saveItem(Item(id: e.id, name: e.name, nameAr: 'رينج 160مم', code: e.code)), throwsA(isA<String>()));
    });

    test('importing by the Arabic name finds the right item', () async {
      final c = VoucherFormCubit(VType.inbound, null);
      await Future<void>.delayed(Duration.zero);
      final missing = await c.importRows(const [ImportRow('فلانشة 160مم', 4)]);
      expect(missing, isEmpty);
      expect(c.state.lines.single.item.code, 'IFLA160.16');
      await c.close();
    });

    test('fill only touches items without an Arabic name', () async {
      final unknown = (await r.allItems()).firstWhere((i) => i.name == 'SOMETHING UNKNOWN');
      await r.saveArabicNames({unknown.id!: 'حاجة يدوي'});
      final before = {for (final i in await r.allItems()) i.id: i.nameAr};
      expect(await r.fillArabicNames(), 0);
      expect({for (final i in await r.allItems()) i.id: i.nameAr}, before);
    });
  });
}
