import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/arabic_names.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'voucher_view_page.dart';

bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;

class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.body, this.actions = const [], this.fab, this.bottom});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? fab, bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: [...actions, const SizedBox(width: 8)]),
        floatingActionButton: fab,
        bottomNavigationBar: bottom,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: body),
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ]),
        ),
      );
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search)),
      );
}

class DateRangeChip extends StatelessWidget {
  const DateRangeChip({super.key, required this.value, required this.onChanged});
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) => InputChip(
        avatar: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text(value == null ? 'كل التواريخ' : '${fmtDate(value!.start)} - ${fmtDate(value!.end)}'),
        onPressed: () async {
          final r = await showDateRangePicker(
              context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: value);
          if (r != null) onChanged(r);
        },
        onDeleted: value == null ? null : () => onChanged(null),
      );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.onTap});
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(label, style: const TextStyle(color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});
  final VType type;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 20,
        backgroundColor: typeColor(type).withValues(alpha: .12),
        child: Icon(typeIcon(type), color: typeColor(type), size: 20),
      );
}

class VoucherTile extends StatelessWidget {
  const VoucherTile(this.v, {super.key});
  final Voucher v;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: TypeBadge(v.type),
        title: Text('${v.title}  •  ${v.isTransfer ? v.notes : (v.partyName.isEmpty ? '-' : v.partyName)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          fmtDate(v.date),
          '${v.lineCount} صنف',
          if (v.refNo.isNotEmpty) 'فاتورة ${v.refNo}',
          if (v.recipientName.isNotEmpty) 'المستلم: ${v.recipientName}',
        ].join('  •  ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(valueLabel(v.total, v.missing), style: TextStyle(fontWeight: FontWeight.w700, color: v.missing ? kOut : null)),
          const Icon(Icons.chevron_left),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherViewPage(id: v.id!))),
      );
}

/// A card that holds a list, with an optional header.
class ListCard extends StatelessWidget {
  const ListCard({super.key, this.title, this.trailing, required this.children});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ?trailing,
              ]),
            ),
          for (var i = 0; i < children.length; i++) ...[if (i > 0 || title != null) const Divider(), children[i]],
        ]),
      );
}

void snack(BuildContext c, String msg, {bool error = false}) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? Theme.of(c).colorScheme.error : null,
  ));

Future<bool> confirm(BuildContext c, String title, String msg, {String ok = 'تأكيد', bool danger = false}) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
            onPressed: () => Navigator.pop(d, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

/// Searchable picker dialog with an optional "add new" row.
Future<T?> pickFrom<T>(
  BuildContext context, {
  required String title,
  required Future<List<T>> Function(String q) load,
  required String Function(T) label,
  String Function(T)? sub,
  Widget Function(T)? trailing,
  String addLabel = 'إضافة جديد',
  Future<T?> Function(String q)? onAdd,
}) =>
    showDialog<T>(
      context: context,
      builder: (_) => _Picker<T>(title, load, label, sub, trailing, addLabel, onAdd),
    );

class _Picker<T> extends StatefulWidget {
  const _Picker(this.title, this.load, this.label, this.sub, this.trailing, this.addLabel, this.onAdd);
  final String title, addLabel;
  final Future<List<T>> Function(String) load;
  final String Function(T) label;
  final String Function(T)? sub;
  final Widget Function(T)? trailing;
  final Future<T?> Function(String)? onAdd;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<_Picker<T>> {
  String q = '';
  late Future<List<T>> f = widget.load('');

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Column(children: [
            ListTile(
              title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'بحث...', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => (q = v, f = widget.load(v))),
              ),
            ),
            if (widget.onAdd != null)
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                title: Text(q.trim().isEmpty ? widget.addLabel : '${widget.addLabel}: «${q.trim()}»'),
                onTap: () async {
                  final r = await widget.onAdd!(q.trim());
                  if (r != null && context.mounted) Navigator.pop(context, r);
                },
              ),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<T>>(
                future: f,
                builder: (_, s) {
                  final list = s.data;
                  if (list == null) return const Center(child: CircularProgressIndicator());
                  if (list.isEmpty) return const EmptyView('مفيش نتايج', icon: Icons.search_off);
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => ListTile(
                      title: Text(widget.label(list[i])),
                      subtitle: widget.sub == null || widget.sub!(list[i]).isEmpty ? null : Text(widget.sub!(list[i])),
                      trailing: widget.trailing?.call(list[i]),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );
}

// ---------------- item & party editors ----------------

Future<Item?> itemDialog(BuildContext context, {Item? item, String name = ''}) =>
    showDialog<Item>(context: context, builder: (_) => _ItemDialog(item, name));

class _ItemDialog extends StatefulWidget {
  const _ItemDialog(this.item, this.name);
  final Item? item;
  final String name;
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final name = TextEditingController(text: widget.item?.name ?? widget.name);
  late final nameAr = TextEditingController(text: widget.item?.nameAr ?? '');
  late final nameEn = TextEditingController(text: widget.item?.nameEn ?? '');
  late final code = TextEditingController(text: widget.item?.code ?? '');
  late final unit = TextEditingController(text: widget.item?.unit ?? 'قطعة');
  late final price = TextEditingController(text: widget.item?.price == null ? '' : fmtQty(widget.item!.price!).replaceAll(',', ''));
  late final min = TextEditingController(text: widget.item == null || widget.item!.minQty == 0 ? '' : fmtQty(widget.item!.minQty));
  String? error;

  Future<void> _save() async {
    if (name.text.trim().isEmpty) return setState(() => error = 'اكتب اسم الصنف');
    final p = price.text.trim().isEmpty ? null : parseNum(price.text);
    if (price.text.trim().isNotEmpty && (p == null || p < 0)) return setState(() => error = 'اكتب السعر رقم صحيح');
    try {
      final it = await Repo.i.saveItem(Item(
        id: widget.item?.id,
        name: name.text,
        nameAr: nameAr.text,
        nameEn: nameEn.text,
        code: code.text,
        unit: unit.text,
        minQty: parseNum(min.text) ?? 0,
        price: p,
      ));
      if (mounted) Navigator.pop(context, it);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'مسح الصنف', 'متأكد إنك عايز تمسح «${widget.item!.title}»؟', ok: 'مسح', danger: true)) return;
    try {
      await Repo.i.deleteItem(widget.item!.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item == null ? 'صنف جديد' : 'تعديل الصنف'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم الصنف *', helperText: 'الاسم الأصلي زي ما في فاتورة المورد'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameAr,
                decoration: InputDecoration(
                  labelText: 'الاسم بالعربي',
                  helperText: 'اللي بيظهر في البرنامج. سيبه فاضي لو الاسم الأصلي عربي',
                  suffixIcon: IconButton(
                    tooltip: 'اقتراح من الاسم الأصلي',
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: () {
                      final s = ArabicNames.suggest(name.text);
                      if (s.isEmpty) return setState(() => error = 'مش لاقي اقتراح للاسم ده، اكتبه بإيدك');
                      setState(() => (nameAr.text = s, error = null));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: nameEn, decoration: const InputDecoration(labelText: 'اسم تاني للبحث (اختياري)')),
              const SizedBox(height: 12),
              TextField(controller: code, decoration: const InputDecoration(labelText: 'كود المورد (اختياري)')),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'السعر (اختياري)', helperText: 'بيظهر تلقائي وقت الاستلام، وتقدر تغيره هناك'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownMenu<String>(
                    controller: unit,
                    label: const Text('الوحدة'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: true,
                    dropdownMenuEntries: [for (final u in units) DropdownMenuEntry(value: u, label: u)],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'حد التنبيه', helperText: 'نبهني لو الرصيد وصل له'),
                  ),
                ),
              ]),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ]),
          ),
        ),
        actions: [
          if (widget.item != null)
            TextButton(onPressed: _delete, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('مسح')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

Future<Party?> partyDialog(BuildContext context, PartyType type, {Party? party, String name = ''}) =>
    showDialog<Party>(context: context, builder: (_) => _PartyDialog(type, party, name));

class _PartyDialog extends StatefulWidget {
  const _PartyDialog(this.type, this.party, this.name);
  final PartyType type;
  final Party? party;
  final String name;
  @override
  State<_PartyDialog> createState() => _PartyDialogState();
}

class _PartyDialogState extends State<_PartyDialog> {
  late final name = TextEditingController(text: widget.party?.name ?? widget.name);
  late final phone = TextEditingController(text: widget.party?.phone ?? '');
  String? error;

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.party == null ? 'إضافة ${widget.type.label}' : 'تعديل ${widget.type.label}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم *')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم التليفون (اختياري)')),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
        actions: [
          if (widget.party != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => _run(() async {
                if (!await confirm(context, 'مسح', 'تمسح «${widget.party!.name}»؟', ok: 'مسح', danger: true)) return;
                await Repo.i.deleteParty(widget.party!.id!);
                if (context.mounted) Navigator.pop(context);
              }),
              child: const Text('مسح'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => _run(() async {
              if (name.text.trim().isEmpty) throw 'اكتب الاسم';
              final p = await Repo.i.saveParty(Party(id: widget.party?.id, type: widget.type, name: name.text, phone: phone.text));
              if (context.mounted) Navigator.pop(context, p);
            }),
            child: const Text('حفظ'),
          ),
        ],
      );
}

/// Picker for a supplier / site / recipient with inline "add new".
Future<Party?> pickParty(BuildContext context, PartyType type) => pickFrom<Party>(
      context,
      title: 'اختار ${type.label}',
      load: (q) => Repo.i.parties([type], q: q),
      label: (p) => p.name,
      sub: (p) => p.phone,
      addLabel: 'إضافة ${type.label}',
      onAdd: (q) => partyDialog(context, type, name: q),
    );

/// Picker for an item (shows current balance) with inline "add new item".
Future<Item?> pickItem(BuildContext context) async => (await pickFrom<ItemStock>(
      context,
      title: 'اختار الصنف',
      load: (q) => Repo.i.stock(q: q, includeEmpty: true),
      label: (s) => s.item.title,
      sub: (s) => s.item.extra,
      trailing: (s) => Text('${fmtQty(s.balance)} ${s.item.unit}',
          style: TextStyle(fontWeight: FontWeight.w700, color: s.balance < 0 ? Colors.red : null)),
      addLabel: 'صنف جديد',
      onAdd: (q) async {
        final it = await itemDialog(context, name: q);
        return it == null ? null : ItemStock(it, 0, 0);
      },
    ))
        ?.item;
