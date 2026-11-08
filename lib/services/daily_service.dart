import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../data/repo.dart';
import 'backup_service.dart';
import 'pdf_service.dart';

/// The nightly stock-count sheet: today's movements, system balance, blank count columns.
class DailyService {
  static const defaultTime = '21:00';

  static Future<String> time() => Repo.i.setting('sheet_time', defaultTime);

  static Future<Uint8List> sheetBytes() async {
    final d = today();
    final stock = await Repo.i.stock();
    final wh = await Repo.i.warehouse(Repo.i.currentWarehouseId);
    // a physical count sheet: system balance, a blank column to write the count, and the gap.
    // Portrait with few columns so item names have room and nothing gets cut off.
    return PdfService.tableBytes(
      'ورقة الجرد اليومي',
      'المخزن: ${wh?.name ?? ''}  -  يوم ${fmtDate(d)}',
      const ['الصنف', 'الوحدة', 'رصيد النظام', 'العدد الفعلي', 'الفرق'],
      [
        for (final s in stock) [s.item.name, s.item.unit, s.balance, '', ''],
      ],
    );
  }

  /// Saves today's sheet (replacing an earlier one from today) and returns its path.
  static Future<String> writeSheet() async {
    final dir = Directory(p.join(await BackupService.usableFolder(), 'جرد'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'جرد_${dbDate(today())}.pdf'));
    await file.writeAsBytes(await sheetBytes(), flush: true);
    await Repo.i.setSetting('sheet_date', dbDate(today()));
    return file.path;
  }

  /// True once the configured time has passed and today's sheet isn't made yet.
  static Future<bool> sheetDue() async {
    if (await Repo.i.setting('sheet_date') == dbDate(today())) return false;
    final parts = (await time()).split(':');
    final at = today().add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
    return !DateTime.now().isBefore(at);
  }
}
