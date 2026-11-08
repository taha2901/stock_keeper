import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/format.dart';
import '../data/repo.dart';
import 'files.dart';

/// Backups are zip files holding the database and the invoice photos.
class BackupService {
  static const keep = 14;
  static const _prefix = 'stock_backup_';

  /// Internal disks other than C:. A flash drive is left out so backups don't
  /// land on something that may be unplugged tomorrow.
  static Future<List<String>> _otherFixedDrives() async {
    if (!Platform.isWindows) return const [];
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-Command', "(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3').DeviceID"]);
      return '${r.stdout}'.split(RegExp(r'\s+')).where((d) => d.length == 2 && d.toUpperCase() != 'C:').map((d) => '$d\\').toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// First of [roots] where the backup folder can be created, else the app's folder on C:.
  static Future<String> pickFolder(List<String> roots) async {
    for (final root in roots) {
      final dir = p.join(root, 'StockKeeperBackups');
      try {
        await Directory(dir).create(recursive: true);
        return dir;
      } catch (_) {}
    }
    return AppDb.backupsDir;
  }

  static Future<String> folder() async {
    final saved = await Repo.i.setting('backup_dir');
    if (saved.isNotEmpty) return saved;
    final found = await pickFolder(await _otherFixedDrives());
    // remembered so backups stay together; falling back to C: isn't, so a disk added later is used
    if (found != AppDb.backupsDir) await Repo.i.setSetting('backup_dir', found);
    return found;
  }

  static bool onSystemDrive(String path) => Platform.isWindows && path.toUpperCase().startsWith('C:');

  /// The configured folder, or the app's own folder if it can't be reached (e.g. flash removed).
  static Future<String> usableFolder() async {
    final f = await folder();
    try {
      await Directory(f).create(recursive: true);
      return f;
    } catch (_) {
      await Directory(AppDb.backupsDir).create(recursive: true);
      return AppDb.backupsDir;
    }
  }

  static Future<List<File>> list() async {
    final dir = Directory(await usableFolder());
    final files = dir.listSync().whereType<File>().where((f) {
      final n = p.basename(f.path);
      return n.startsWith(_prefix) && n.endsWith('.zip');
    }).toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  static Future<Uint8List> _zip() {
    final db = AppDb.path, photos = AppDb.attachmentsDir;
    return Isolate.run(() {
      final a = Archive();
      final dbBytes = File(db).readAsBytesSync();
      a.addFile(ArchiveFile('stock.db', dbBytes.length, dbBytes));
      final dir = Directory(photos);
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          final b = f.readAsBytesSync();
          a.addFile(ArchiveFile('attachments/${p.basename(f.path)}', b.length, b));
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(a)!);
    });
  }

  /// Writes a backup and keeps only the newest [keep]. [kind] is auto, manual or close.
  static Future<String> create(String kind) async {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final dir = await usableFolder();
    final path = p.join(dir, '$_prefix${dbDate(now)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}_$kind.zip');
    await File(path).writeAsBytes(await _zip(), flush: true);
    for (final f in (await list()).skip(keep)) {
      await f.delete();
    }
    return path;
  }

  /// One automatic backup per day.
  static Future<void> autoBackup() async {
    if (!await File(AppDb.path).exists()) return;
    final today = '$_prefix${dbDate(DateTime.now())}_';
    final done = (await list()).any((f) {
      final n = p.basename(f.path);
      return n.startsWith(today) && n.endsWith('_auto.zip');
    });
    if (!done) await create('auto');
  }

  /// Saves a copy wherever the user chooses (flash, OneDrive...).
  static Future<bool> exportBackup() async =>
      saveBytes('$_prefix${dbDate(DateTime.now())}.zip', await _zip(), initialDirectory: await usableFolder());

  /// Replaces current data with a backup (.zip, or an older .db). Returns false if cancelled.
  static Future<bool> restore() async {
    final bytes = await pickBytes(initialDirectory: await usableFolder());
    if (bytes == null) return false;
    await restoreBytes(bytes);
    return true;
  }

  static bool _isSqlite(List<int> b) => b.length >= 15 && String.fromCharCodes(b.sublist(0, 15)) == 'SQLite format 3';

  static Future<void> restoreBytes(Uint8List bytes) async {
    List<int>? db;
    Archive? zip;
    if (_isSqlite(bytes)) {
      db = bytes;
    } else {
      try {
        zip = ZipDecoder().decodeBytes(bytes);
        final entry = zip.findFile('stock.db');
        if (entry != null) db = entry.content as List<int>;
      } catch (_) {}
    }
    if (db == null || !_isSqlite(db)) throw 'الملف ده مش نسخة احتياطية من البرنامج';

    final safety = await usableFolder(); // read before the database closes
    await AppDb.close();
    await File(AppDb.path).copy(p.join(safety, 'before_restore_${DateTime.now().millisecondsSinceEpoch}.db'));
    await File(AppDb.path).writeAsBytes(db, flush: true);
    if (zip != null) {
      for (final f in zip.files.where((f) => f.isFile && f.name.startsWith('attachments/'))) {
        await File(p.join(AppDb.attachmentsDir, p.basename(f.name))).writeAsBytes(f.content as List<int>);
      }
    }
    await AppDb.open();
    // photo paths are absolute: point them at this device's folder
    final rows = await AppDb.db.query('vouchers', columns: ['id', 'attachment'], where: 'attachment IS NOT NULL');
    for (final r in rows) {
      final name = (r['attachment'] as String).split(RegExp(r'[\\/]')).last;
      await AppDb.db.update('vouchers', {'attachment': p.join(AppDb.attachmentsDir, name)}, where: 'id=?', whereArgs: [r['id']]);
    }
    Repo.i.notify();
  }
}
