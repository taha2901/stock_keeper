import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'widgets.dart';

class _TLine {
  final ItemStock stock;
  double qty = 0;
  _TLine(this.stock);
}

/// Move items from one warehouse to another in one step.
class TransferPage extends StatefulWidget {
  const TransferPage({super.key});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  List<Warehouse> _all = const [];
  int? fromWh, toWh;
  DateTime date = today();
  final notes = TextEditingController();
  final lines = <_TLine>[];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    Repo.i.warehouses().then((all) {
      if (!mounted) return;
      setState(() {
        _all = all;
        fromWh = Repo.i.currentWarehouseId;
        toWh = all.where((w) => w.id != fromWh).map((w) => w.id).firstOrNull;
      });
    });
  }

  Future<void> _addItem() async {
    if (fromWh == null) return;
    final picked = await pickFrom<ItemStock>(
      context,
      title: 'اختار صنف من المصدر',
      load: (q) async => (await Repo.i.stock(q: q, warehouseId: fromWh)).where((s) => s.balance > 0).toList(),
      label: (s) => s.item.title,
      sub: (s) => s.item.extra,
      trailing: (s) => Text('${fmtQty(s.balance)} ${s.item.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
    if (picked == null) return;
    if (lines.any((l) => l.stock.item.id == picked.item.id)) {
      if (mounted) snack(context, 'الصنف مضاف بالفعل');
      return;
    }
    setState(() => lines.add(_TLine(picked)));
  }

  Future<void> _save() async {
    if (fromWh == null || toWh == null) return snack(context, 'اختار المخزنين', error: true);
    if (fromWh == toWh) return snack(context, 'المصدر والوجهة لازم مختلفين', error: true);
    if (lines.isEmpty) return snack(context, 'ضيف صنف واحد على الأقل', error: true);
    setState(() => saving = true);
    try {
      await Repo.i.transfer(
        fromWh: fromWh!,
        toWh: toWh!,
        date: date,
        notes: notes.text,
        lines: [for (final l in lines) MapEntry(l.stock.item, l.qty)],
      );
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'تم التحويل بنجاح');
      }
    } catch (e) {
      if (mounted) snack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fw = isWide(context) ? 300.0 : double.infinity;
    Widget whField(String label, int? value, ValueChanged<int?> onChanged, {int? exclude}) => SizedBox(
          width: fw,
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.warehouse_outlined)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: value,
                items: [
                  for (final w in _all.where((w) => w.id != exclude))
                    DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        );

    return PageScaffold(
      title: 'تحويل بين المخازن',
      bottom: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
        padding: const EdgeInsets.all(12),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(child: Text('${lines.length} صنف', style: const TextStyle(fontWeight: FontWeight.w600))),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.swap_horiz),
              label: const Text('تنفيذ التحويل'),
            ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              whField('من مخزن *', fromWh, (v) async {
                setState(() {
                  fromWh = v;
                  if (toWh == v) toWh = _all.where((w) => w.id != v).map((w) => w.id).firstOrNull;
                  lines.clear();
                });
              }, exclude: null),
              whField('إلى مخزن *', toWh, (v) => setState(() => toWh = v), exclude: fromWh),
              SizedBox(
                width: fw,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => date = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'التاريخ', prefixIcon: Icon(Icons.event)),
                    child: Text(fmtDate(date)),
                  ),
                ),
              ),
              SizedBox(
                width: fw,
                child: TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes))),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ListCard(title: 'الأصناف (${lines.length})', children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.tonalIcon(onPressed: fromWh == null ? null : _addItem, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
          ),
          if (lines.isEmpty) const EmptyView('لسه مفيش أصناف\nدوس «إضافة صنف» واختار من المصدر', icon: Icons.playlist_add),
          for (var i = 0; i < lines.length; i++) _row(i),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _row(int i) {
    final l = lines[i];
    final avail = l.stock.balance;
    final over = l.qty > avail + 1e-6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: kBg, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.stock.item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (l.stock.item.extra.isNotEmpty)
              Text(l.stock.item.extra, style: const TextStyle(fontSize: 11.5, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('المتاح في المصدر: ${fmtQty(avail)} ${l.stock.item.unit}',
                style: TextStyle(fontSize: 12, color: over ? Colors.red : Colors.black54)),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextField(
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'الكمية',
              suffixText: l.stock.item.unit,
              errorText: over ? 'أكبر من المتاح' : null,
              errorStyle: const TextStyle(fontSize: 10),
            ),
            onChanged: (v) => setState(() => l.qty = parseNum(v) ?? 0),
          ),
        ),
        IconButton(onPressed: () => setState(() => lines.removeAt(i)), icon: const Icon(Icons.close, color: Colors.black45)),
      ]),
    );
  }
}
