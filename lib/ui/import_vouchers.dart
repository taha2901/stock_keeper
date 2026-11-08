import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../services/excel_service.dart';
import '../services/files.dart';
import 'warehouses_page.dart';
import 'widgets.dart';

/// Reusable "import inbound from an Excel file" flow, used from the الوارد page.
Future<void> importInboundFlow(BuildContext context) async {
  final picked = await pickNamed(extensions: ['xlsx', 'pdf']);
  if (picked == null || !context.mounted) return;

  if (picked.name.toLowerCase().endsWith('.pdf')) {
    snack(context, 'الاستيراد من ملف Excel بس دلوقتي. لو معاك PDF، استخدم ملف الإكسيل اللي اتبعتلك.', error: true);
    return;
  }

  final skipped = <String>[];
  List<ImportVoucher> vouchers;
  try {
    vouchers = ExcelService.parseVouchers(picked.bytes, skipped: skipped);
  } catch (_) {
    if (context.mounted) snack(context, 'الملف ده مش مقروء. استخدم ملف Excel (.xlsx) بنفس أعمدة النموذج.', error: true);
    return;
  }
  if (vouchers.isEmpty) {
    if (context.mounted) snack(context, 'مفيش بيانات في الملف.${skipped.isEmpty ? '' : ' ${skipped.length} صف متقراش.'}', error: true);
    return;
  }

  // choose the destination warehouse (only asks when there's more than one)
  final all = await Repo.i.warehouses();
  if (!context.mounted) return;
  Warehouse target;
  if (all.length == 1) {
    target = all.first;
  } else {
    final picked2 = await pickWarehouse(context);
    if (picked2 == null) return;
    target = picked2;
  }

  final totalLines = vouchers.fold(0, (a, v) => a + v.lineCount);
  if (!context.mounted) return;
  final ok = await confirm(
    context,
    'استيراد الوارد',
    'هيتسجل ${vouchers.length} سند استلام و$totalLines بند في مخزن «${target.name}».'
        '${skipped.isEmpty ? '' : '\n${skipped.length} صف هيتساب (كمية أو بيانات ناقصة).'}'
        '\n\nتكمل؟',
    ok: 'استيراد',
  );
  if (!ok) return;

  try {
    final res = await Repo.i.importVouchers(vouchers, target.id!);
    if (context.mounted) {
      snack(context,
          'تم: ${res['vouchers']} سند، ${res['lines']} بند، ${res['newItems']} صنف جديد، ${res['newSuppliers']} مورد جديد.');
    }
  } catch (e) {
    if (context.mounted) snack(context, 'حصل خطأ في الاستيراد: $e', error: true);
  }
}

/// A small example workbook so the keeper can see the expected columns.
Future<void> downloadImportTemplate(BuildContext context) async {
  final rows = <List<Object?>>[
    ['مؤسسة سند', DateTime(2026, 8, 26), '261040', '', 'فلانج ادابتور 160 مم', '', 'قطعة', 4, 37.75],
    ['مؤسسة سند', DateTime(2026, 8, 26), '261040', '', 'رينج 160 مم', '', 'قطعة', 4, 100.0],
    ['الاتحاد لصناعة الأنابيب', DateTime(2026, 9, 14), 'WH/OUT/14151', '', 'ماسورة 200 مم', '[P8-4BL-200-16-12]', 'متر', 200, null],
  ];
  if (await saveBytes('نموذج_استيراد_الوارد.xlsx', ExcelService.vouchersWorkbook(rows)) && context.mounted) {
    snack(context, 'اتحفظ النموذج. كل صف = بند. السندات بتتجمع بالمورد + رقم الفاتورة + التاريخ.');
  }
}
