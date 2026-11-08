import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../cubits/voucher_form_cubit.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../services/excel_service.dart';
import '../services/files.dart';
import '../services/pdf_service.dart';
import 'warehouses_page.dart';
import 'widgets.dart';

/// Opens the form; after saving a new issue voucher, offers to print it.
Future<void> openVoucherForm(BuildContext context, VType type, {int? id}) async {
  final saved = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => VoucherFormPage(type: type, id: id)));
  if (saved == null || !context.mounted) return;
  snack(context, 'اتحفظ ${type.doc} بنجاح');
  if (!type.isIn && id == null && await confirm(context, 'طباعة', 'تطبع إذن الصرف دلوقتي؟', ok: 'طباعة')) {
    await PdfService.printVoucher(saved);
  }
}

class VoucherFormPage extends StatelessWidget {
  const VoucherFormPage({super.key, required this.type, this.id});
  final VType type;
  final int? id;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => VoucherFormCubit(type, id),
        child: BlocConsumer<VoucherFormCubit, VForm>(
          listenWhen: (a, b) => b.savedId != null || b.duplicate != null || b.dateWarning != null || b.error != null,
          listener: (context, s) async {
            if (s.savedId != null) Navigator.pop(context, s.savedId);
            if (s.error != null) snack(context, s.error!, error: true);
            if (s.duplicate != null) {
              final cubit = context.read<VoucherFormCubit>();
              if (await confirm(context, 'فاتورة مكررة', s.duplicate!, ok: 'احفظ برضو')) cubit.save(force: true, dateOk: true);
            }
            if (s.dateWarning != null && context.mounted) {
              final cubit = context.read<VoucherFormCubit>();
              if (await confirm(context, 'راجع التاريخ', s.dateWarning!, ok: 'احفظ برضو')) cubit.save(dateOk: true);
            }
          },
          buildWhen: (a, b) => a.loading != b.loading,
          builder: (context, s) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final nav = Navigator.of(context);
              if (!context.read<VoucherFormCubit>().dirty ||
                  await confirm(context, 'خروج من غير حفظ', 'في تعديلات لسه ما اتحفظتش وهتضيع. تخرج برضو؟', ok: 'اخرج', danger: true)) {
                nav.pop();
              }
            },
            child: PageScaffold(
              title: id == null ? '${type.doc} جديد' : 'تعديل ${type.doc} رقم ${s.number}',
              body: s.loading ? const Center(child: CircularProgressIndicator()) : const _Body(),
              bottom: s.loading ? null : const _SaveBar(),
            ),
          ),
        ),
      );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<VoucherFormCubit>().state;
    final total = s.lines.fold(0.0, (a, l) => a + l.total);
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: Text(s.type.isIn ? '${s.lines.length} صنف  •  الإجمالي ${fmtMoney(total)} ريال' : '${s.lines.length} صنف',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: typeColor(s.type), minimumSize: const Size(160, 48)),
            onPressed: s.saving ? null : context.read<VoucherFormCubit>().save,
            icon: s.saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('حفظ'),
          ),
        ]),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VoucherFormCubit>();
    final s = context.watch<VoucherFormCubit>().state;
    final wide = isWide(context);
    final fw = wide ? 340.0 : double.infinity;
    final t = s.type;

    Widget field(String label, String? value, IconData icon, VoidCallback onTap, {VoidCallback? onClear}) => SizedBox(
          width: fw,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                suffixIcon: onClear != null && value != null ? IconButton(icon: const Icon(Icons.close), onPressed: onClear) : null,
              ),
              child: Text(value ?? 'اختار...', style: TextStyle(color: value == null ? Colors.black38 : null)),
            ),
          ),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            field('المخزن *', s.warehouseName.isEmpty ? null : s.warehouseName, Icons.warehouse_outlined, () async {
              final w = await pickWarehouse(context);
              if (w != null) cubit.setWarehouse(w);
            }),
            field('التاريخ', fmtDate(s.date), Icons.event, () async {
              final d = await showDatePicker(context: context, initialDate: s.date, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) cubit.setDate(d);
            }),
            field('${t.partyType.label} *', s.party?.name, t.isIn ? Icons.local_shipping_outlined : Icons.location_on_outlined, () async {
              final p = await pickParty(context, t.partyType);
              if (p != null) cubit.setParty(p);
            }),
            if (!t.isIn)
              field('المستلم', s.recipient?.name, Icons.person_outline, () async {
                final p = await pickParty(context, PartyType.recipient);
                if (p != null) cubit.setRecipient(p);
              }, onClear: () => cubit.setRecipient(null)),
            SizedBox(
              width: fw,
              child: TextFormField(
                initialValue: s.refNo,
                onChanged: cubit.setRef,
                decoration: InputDecoration(
                  labelText: t.isIn ? 'رقم الفاتورة / إذن التسليم' : 'رقم مرجعي (اختياري)',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                ),
              ),
            ),
            SizedBox(
              width: fw,
              child: TextFormField(
                initialValue: s.licenseNo,
                onChanged: cubit.setLicense,
                decoration: const InputDecoration(labelText: 'رقم الرخصة (اختياري)', prefixIcon: Icon(Icons.badge_outlined)),
              ),
            ),
            SizedBox(
              width: fw,
              child: TextFormField(
                initialValue: s.notes,
                onChanged: cubit.setNotes,
                decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes)),
              ),
            ),
            if (t.isIn) _Attachment(path: s.attachment, width: fw),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ListCard(
        title: 'الأصناف (${s.lines.length})',
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final it = await pickItem(context);
                  if (it != null) await cubit.addItem(it);
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
              OutlinedButton.icon(onPressed: () => _import(context), icon: const Icon(Icons.upload_file), label: const Text('استيراد من Excel')),
              TextButton.icon(
                onPressed: () async {
                  if (await saveBytes('نموذج_استيراد_الأصناف.xlsx', ExcelService.template()) && context.mounted) {
                    snack(context, 'اتحفظ النموذج. املاه وارجع دوس «استيراد من Excel»');
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('تحميل نموذج Excel'),
              ),
            ]),
          ),
          if (!t.isIn && s.lines.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('السعر بيتحسب تلقائي بعد الحفظ: الوارد أولًا صادر أولًا.', style: TextStyle(color: Colors.black54)),
            ),
          if (s.lines.isEmpty) const EmptyView('لسه مفيش أصناف\nدوس «إضافة صنف» أو استورد من Excel', icon: Icons.playlist_add),
          for (var i = 0; i < s.lines.length; i++) _LineRow(key: ValueKey(s.lines[i].uid), index: i, line: s.lines[i], type: t),
        ],
      ),
      const SizedBox(height: 24),
    ]);
  }

  Future<void> _import(BuildContext context) async {
    final cubit = context.read<VoucherFormCubit>();
    final bytes = await pickBytes(extensions: ['xlsx']);
    if (bytes == null || !context.mounted) return;
    List<ImportRow> rows;
    final skipped = <String>[];
    try {
      rows = ExcelService.parse(bytes, skipped: skipped);
    } catch (_) {
      if (context.mounted) snack(context, 'الملف ده مش مقروء. استخدم ملف Excel (.xlsx)', error: true);
      return;
    }
    if (rows.isEmpty) {
      if (context.mounted) snack(context, 'مفيش أصناف في الملف. العمود الأول الصنف والتاني الكمية.', error: true);
      return;
    }
    var missing = await cubit.importRows(rows);
    if (missing.isNotEmpty && context.mounted) {
      final names = missing.map((r) => '• ${r.name}').take(15).join('\n');
      final add = await confirm(context, 'أصناف جديدة',
          'الأصناف دي مش موجودة في دليل الأصناف:\n$names${missing.length > 15 ? '\n...' : ''}\n\nتضيفها كأصناف جديدة؟',
          ok: 'إضافة');
      if (add) {
        for (final r in missing) {
          try {
            await Repo.i.saveItem(Item(name: r.name, unit: r.unit.isEmpty ? 'قطعة' : r.unit));
          } catch (_) {}
        }
        missing = await cubit.importRows(missing);
      }
    }
    if (!context.mounted) return;
    if (skipped.isEmpty) return snack(context, 'اتضاف ${rows.length - missing.length} صنف من الملف');
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('اتضاف ${rows.length - missing.length} صنف، و${skipped.length} صف متقراش'),
        content: SingleChildScrollView(child: Text('راجع الكمية أو اسم الصنف في الصفوف دي:\n${skipped.join('\n')}')),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('تمام'))],
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.path, required this.width});
  final String? path;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VoucherFormCubit>();
    return SizedBox(
      width: width,
      child: path == null
          ? OutlinedButton.icon(
              onPressed: () async {
                final p = await pickAttachment();
                if (p != null) cubit.setAttachment(p);
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('إرفاق صورة الفاتورة'),
            )
          : Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(path!), width: 48, height: 48, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('صورة الفاتورة مرفقة')),
              IconButton(tooltip: 'إزالة', onPressed: () => cubit.setAttachment(null), icon: const Icon(Icons.delete_outline)),
            ]),
    );
  }
}

class _LineRow extends StatefulWidget {
  const _LineRow({super.key, required this.index, required this.line, required this.type});
  final int index;
  final FLine line;
  final VType type;
  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  String _num(double v) => fmtQty(v).replaceAll(',', '');
  late final qty = TextEditingController(text: widget.line.qty == 0 ? '' : _num(widget.line.qty));
  late final price = TextEditingController(text: widget.line.price == null ? '' : _num(widget.line.price!));

  @override
  void didUpdateWidget(covariant _LineRow old) {
    super.didUpdateWidget(old);
    // values changed from outside (e.g. the same item imported twice)
    if (parseNum(qty.text) != widget.line.qty && widget.line.qty != 0) qty.text = _num(widget.line.qty);
    if (widget.line.price != null && parseNum(price.text) != widget.line.price) price.text = _num(widget.line.price!);
  }

  @override
  void dispose() {
    qty.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final cubit = context.read<VoucherFormCubit>();
    final isIn = widget.type.isIn;
    final over = !isIn && l.qty > l.available + 1e-6;
    final after = isIn ? l.available + l.qty : l.available - l.qty;
    final info = Row(children: [
      CircleAvatar(radius: 14, backgroundColor: kBg, child: Text('${widget.index + 1}', style: const TextStyle(fontSize: 12))),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (l.item.extra.isNotEmpty) Text(l.item.extra, style: const TextStyle(fontSize: 11.5, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            'الرصيد: ${fmtQty(l.available)} ← ${fmtQty(after)} ${l.item.unit}${isIn && l.price != null ? '  •  ${fmtMoney(l.total)} ريال' : ''}',
            style: TextStyle(fontSize: 12, color: over ? Colors.red : Colors.black54, fontWeight: over ? FontWeight.w700 : null),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    ]);
    final qtyField = TextField(
      controller: qty,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'الكمية',
        suffixText: l.item.unit,
        errorText: over ? 'أكبر من الرصيد' : null,
        errorStyle: const TextStyle(fontSize: 10),
      ),
      onChanged: (v) => cubit.setQty(l.uid, parseNum(v) ?? 0),
    );
    final priceField = TextField(
      controller: price,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'السعر'),
      onChanged: (v) => cubit.setPrice(l.uid, parseNum(v)),
    );
    final del = IconButton(tooltip: 'حذف', onPressed: () => cubit.remove(l.uid), icon: const Icon(Icons.close, color: Colors.black45));

    if (isWide(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Expanded(child: info),
          const SizedBox(width: 8),
          SizedBox(width: 130, child: qtyField),
          if (isIn) ...[const SizedBox(width: 8), SizedBox(width: 120, child: priceField)],
          del,
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(children: [
        info,
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: qtyField),
          if (isIn) ...[const SizedBox(width: 8), Expanded(child: priceField)],
          del,
        ]),
      ]),
    );
  }
}
