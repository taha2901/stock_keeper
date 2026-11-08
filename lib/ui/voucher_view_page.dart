import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../services/pdf_service.dart';
import 'export_menu.dart';
import 'voucher_form_page.dart';
import 'widgets.dart';

class VoucherViewPage extends StatefulWidget {
  const VoucherViewPage({super.key, required this.id});
  final int id;
  @override
  State<VoucherViewPage> createState() => _VoucherViewPageState();
}

class _VoucherViewPageState extends State<VoucherViewPage> {
  late Future<Voucher> f = Repo.i.voucher(widget.id);
  late final StreamSubscription<void> sub = Repo.i.changes.listen((_) {
    if (mounted) setState(() => f = Repo.i.voucher(widget.id));
  });

  @override
  void initState() {
    super.initState();
    sub;
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  Future<void> _delete(Voucher v) async {
    if (!await confirm(context, 'مسح ${v.type.doc}', 'متأكد إنك عايز تمسح ${v.title}؟ الرصيد هيتعدل تلقائي.', ok: 'مسح', danger: true)) return;
    try {
      await Repo.i.deleteVoucher(v.id!);
    } catch (e) {
      if (mounted) snack(context, '$e', error: true);
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      snack(context, 'اتمسح ${v.title}');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Voucher>(
        future: f,
        builder: (context, s) {
          final v = s.data;
          if (s.hasError) return PageScaffold(title: 'السند', body: EmptyView('${s.error}', icon: Icons.error_outline));
          if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          Widget info(String k, String val) => SizedBox(
                width: isWide(context) ? 260 : double.infinity,
                child: ListTile(dense: true, title: Text(k, style: const TextStyle(color: Colors.black54)), subtitle: Text(val.isEmpty ? '-' : val, style: const TextStyle(fontSize: 15, color: Colors.black87))),
              );
          return PageScaffold(
            title: v.title,
            actions: [
              ExportMenu(
                pdf: () => PdfService.voucherBytes(v.id!),
                data: ExportData(
                  title: v.title,
                  subtitle: '${fmtDate(v.date)} - ${v.partyName}',
                  headers: const ['م', 'الصنف', 'الكود', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي', 'ملاحظات'],
                  rows: [
                    for (var i = 0; i < v.lines.length; i++)
                      [i + 1, v.lines[i].item.label, v.lines[i].item.code, v.lines[i].item.unit, v.lines[i].qty, priceLabel(v.lines[i].cost), v.lines[i].cost.value, v.lines[i].note],
                    ['الإجمالي', null, null, null, null, null, v.total, null],
                  ],
                ),
              ),
              IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print_outlined), onPressed: () => PdfService.printVoucher(v.id!)),
              IconButton(
                tooltip: v.isTransfer ? 'التحويل مينفعش يتعدل' : 'تعديل',
                icon: const Icon(Icons.edit_outlined),
                onPressed: v.isTransfer
                    ? () => snack(context, 'ده تحويل بين المخازن، مينفعش يتعدل. امسحه واعمل تحويل جديد بالكميات الصح.', error: true)
                    : () => openVoucherForm(context, v.type, id: v.id),
              ),
              IconButton(tooltip: 'مسح', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(v)),
            ],
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(children: [
                    ListTile(leading: TypeBadge(v.type), title: Text(v.type.label, style: TextStyle(color: typeColor(v.type), fontWeight: FontWeight.w700))),
                    info('المخزن', v.warehouseName),
                    info('التاريخ', fmtDate(v.date)),
                    info(v.type.partyType.label, v.partyName),
                    if (!v.type.isIn) info('المستلم', v.recipientName),
                    info(v.type.isIn ? 'رقم الفاتورة' : 'رقم مرجعي', v.refNo),
                    if (v.licenseNo.isNotEmpty) info('رقم الرخصة', v.licenseNo),
                    info('ملاحظات', v.notes),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              ListCard(title: 'الأصناف (${v.lines.length})', children: [
                for (var i = 0; i < v.lines.length; i++)
                  ListTile(
                    leading: CircleAvatar(radius: 14, backgroundColor: kBg, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    title: Text(v.lines[i].item.title),
                    subtitle: Text([
                      priceLabel(v.lines[i].cost, sep: '  +  '),
                      v.lines[i].item.extra,
                      v.lines[i].note,
                    ].where((e) => e.isNotEmpty).join('  •  ')),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${fmtQty(v.lines[i].qty)} ${v.lines[i].item.unit}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(valueLabel(v.lines[i].cost.value, v.lines[i].cost.missing), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                ListTile(
                  title: const Text('إجمالي القيمة', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: v.missing ? const Text('* فيه كميات بدون سعر ومش داخلة في الإجمالي', style: TextStyle(color: kOut)) : null,
                  trailing: Text('${valueLabel(v.total, v.missing)} ريال', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ]),
              if (v.attachment != null) ...[
                const SizedBox(height: 12),
                ListCard(title: 'صورة الفاتورة', children: [
                  InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(child: InteractiveViewer(child: Image.file(File(v.attachment!)))),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.file(File(v.attachment!), height: 220, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const EmptyView('الصورة مش موجودة', icon: Icons.broken_image_outlined)),
                    ),
                  ),
                ]),
              ],
            ]),
          );
        },
      );
}
