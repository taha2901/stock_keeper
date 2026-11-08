import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// sqflite registers the native factory on Android/iOS; ffi is used on desktop.
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite database (one file on the device). The stock balance is never stored:
/// it is always computed from the voucher lines, so it can't drift.
class AppDb {
  AppDb._();
  static Database? _db;
  static late String dir;

  static Database get db => _db!;
  static String get path => p.join(dir, 'stock.db');
  static String get attachmentsDir => p.join(dir, 'attachments');
  static String get backupsDir => p.join(dir, 'backups');

  static Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    dir = (await getApplicationSupportDirectory()).path;
    await Directory(attachmentsDir).create(recursive: true);
    await Directory(backupsDir).create(recursive: true);
    await open();
  }

  static Future<void> open() async {
    _db = await openDatabase(
      path,
      version: 5,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// v2 adds the purchase price per line (NULL = no price entered yet).
  static Future<void> _upgrade(Database d, int from, int to) async {
    if (from < 2) await d.execute('ALTER TABLE voucher_lines ADD COLUMN price REAL');
    if (from < 3) await d.execute('ALTER TABLE items ADD COLUMN price REAL');
    if (from < 4) {
      await d.execute('''CREATE TABLE warehouses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL)''');
      final id = await d.insert('warehouses', {'name': 'المخزن الرئيسي', 'created_at': DateTime.now().toIso8601String()});
      await d.execute('ALTER TABLE vouchers ADD COLUMN warehouse_id INTEGER');
      await d.execute('ALTER TABLE vouchers ADD COLUMN license_no TEXT NOT NULL DEFAULT \'\'');
      await d.update('vouchers', {'warehouse_id': id});
      await d.insert('settings', {'key': 'current_wh', 'value': '\$id'}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (from < 5) await d.execute('ALTER TABLE vouchers ADD COLUMN transfer_id INTEGER');
  }

  static Future<void> _create(Database d, int version) async {
    final b = d.batch()
      ..execute('''CREATE TABLE warehouses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL)''')
      ..insert('warehouses', {'name': 'المخزن الرئيسي', 'created_at': DateTime.now().toIso8601String()})
      ..execute('''CREATE TABLE items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        name_en TEXT NOT NULL DEFAULT '',
        code TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT 'قطعة',
        min_qty REAL NOT NULL DEFAULT 0,
        price REAL)''')
      ..execute('''CREATE TABLE parties(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        phone TEXT NOT NULL DEFAULT '',
        UNIQUE(type, name))''')
      ..execute('''CREATE TABLE vouchers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        number INTEGER NOT NULL,
        date TEXT NOT NULL,
        warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
        party_id INTEGER REFERENCES parties(id),
        recipient_id INTEGER REFERENCES parties(id),
        ref_no TEXT NOT NULL DEFAULT '',
        license_no TEXT NOT NULL DEFAULT '',
        transfer_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        attachment TEXT,
        created_at TEXT NOT NULL)''')
      ..execute('''CREATE TABLE voucher_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_id INTEGER NOT NULL REFERENCES vouchers(id) ON DELETE CASCADE,
        item_id INTEGER NOT NULL REFERENCES items(id),
        qty REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        price REAL)''')
      ..execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute('CREATE INDEX ix_lines_item ON voucher_lines(item_id)')
      ..execute('CREATE INDEX ix_lines_voucher ON voucher_lines(voucher_id)')
      ..execute('CREATE INDEX ix_vouchers_type_date ON vouchers(type, date)')
      ..execute('CREATE INDEX ix_vouchers_wh ON vouchers(warehouse_id)');
    await b.commit(noResult: true);
  }
}
