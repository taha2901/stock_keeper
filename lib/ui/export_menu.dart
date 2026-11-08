import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../services/excel_service.dart';
import '../services/files.dart';
import '../services/pdf_service.dart';
import 'widgets.dart';

class ExportData {
  const ExportData({required this.title, this.subtitle = '', required this.headers, required this.rows});
  final String title, subtitle;
  final List<String> headers;
  final List<List<Object?>> rows;
}

/// "تصدير" menu used on every screen: Excel, PDF, and print.
/// [pdf] overrides the default table layout (used for printable vouchers).
class ExportMenu extends StatelessWidget {
  const ExportMenu({super.key, required this.data, this.pdf});
  final ExportData? data;
  final Future<Uint8List> Function()? pdf;

  Future<void> _run(BuildContext context, String action) async {
    final d = data!;
    final name = '${d.title}_${dbDate(DateTime.now())}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    try {
      if (action == 'xlsx') {
        final sheet = d.title.replaceAll(RegExp(r'[\\/:*?\[\]]'), '-');
        final ok = await saveBytes('$name.xlsx', ExcelService.table(sheet.length > 30 ? sheet.substring(0, 30) : sheet, d.headers, d.rows));
        if (ok && context.mounted) snack(context, 'اتحفظ ملف Excel');
        return;
      }
      final bytes = pdf != null ? await pdf!() : await PdfService.tableBytes(d.title, d.subtitle, d.headers, d.rows);
      if (action == 'print') {
        await PdfService.printBytes(bytes, name);
      } else if (await saveBytes('$name.pdf', bytes) && context.mounted) {
        snack(context, 'اتحفظ ملف PDF');
      }
    } catch (e) {
      if (context.mounted) snack(context, 'حصل خطأ: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = data != null && data!.rows.isNotEmpty;
    PopupMenuItem<String> item(String v, IconData i, String t) =>
        PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 20), const SizedBox(width: 10), Text(t)]));
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'تصدير وطباعة',
      onSelected: (a) => _run(context, a),
      itemBuilder: (_) => [
        item('xlsx', Icons.table_chart_outlined, 'تصدير Excel'),
        item('pdf', Icons.picture_as_pdf_outlined, 'تصدير PDF'),
        item('print', Icons.print_outlined, 'طباعة'),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.file_download_outlined, color: enabled ? null : Colors.black26),
          const SizedBox(width: 4),
          Text('تصدير', style: TextStyle(color: enabled ? null : Colors.black26)),
        ]),
      ),
    );
  }
}
