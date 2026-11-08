import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/arabic_names.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'widgets.dart';

/// How item names are shown (Arabic / English / both), as a segmented control.
class NameModePicker extends StatefulWidget {
  const NameModePicker({super.key});
  @override
  State<NameModePicker> createState() => _NameModePickerState();
}

class _NameModePickerState extends State<NameModePicker> {
  @override
  Widget build(BuildContext context) => SegmentedButton<NameMode>(
        showSelectedIcon: false,
        segments: [for (final m in NameMode.values) ButtonSegment(value: m, label: Text(m.label))],
        selected: {Item.mode},
        onSelectionChanged: (v) async {
          await Repo.i.setNameMode(v.first);
          if (mounted) setState(() {});
        },
      );
}

/// Review screen: every item's original (English) name next to its Arabic name.
/// Nothing is saved until «حفظ»; two items can never end up with the same name.
class ItemNamesPage extends StatefulWidget {
  const ItemNamesPage({super.key});
  @override
  State<ItemNamesPage> createState() => _ItemNamesPageState();
}

class _ItemNamesPageState extends State<ItemNamesPage> {
  List<Item>? items;
  final ctl = <int, TextEditingController>{};
  String q = '';
  bool emptyOnly = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final all = await Repo.i.allItems();
    if (!mounted) return;
    setState(() {
      items = all;
      for (final it in all) {
        ctl.putIfAbsent(it.id!, () => TextEditingController(text: it.nameAr))
          ..text = it.nameAr
          ..addListener(() => setState(() {}));
      }
    });
  }

  Map<int, String> get _changed => {
        for (final it in items ?? <Item>[])
          if (ctl[it.id!]!.text.trim() != it.nameAr.trim()) it.id!: ctl[it.id!]!.text.trim(),
      };

  bool _empty(Item it) => ctl[it.id!]!.text.trim().isEmpty && !ArabicNames.isArabic(it.name);

  /// Fills the empty ones with suggestions that don't clash with any name in use.
  void _suggest() {
    final list = items!;
    final taken = <String>{
      for (final it in list)
        if (ctl[it.id!]!.text.trim().isNotEmpty) ctl[it.id!]!.text.trim() else if (ArabicNames.isArabic(it.name)) it.name.trim(),
    };
    final s = ArabicNames.uniqueAll([for (final it in list) if (_empty(it)) (id: it.id!, name: it.name, code: it.code)], taken: taken);
    s.forEach((id, n) => ctl[id]!.text = n);
    final left = list.where(_empty).length;
    snack(context, 'اتملى ${s.length} اسم. ${left == 0 ? 'راجعهم ودوس حفظ.' : 'فاضل $left مش لاقي له اقتراح، اكتبهم بإيدك.'}');
  }

  Future<void> _save() async {
    final changes = _changed;
    if (changes.isEmpty) return;
    setState(() => saving = true);
    try {
      await Repo.i.saveArabicNames(changes);
      await _load();
      if (mounted) snack(context, 'اتحفظ ${changes.length} اسم');
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('مينفعش يتحفظ'),
            content: Text('$e'),
            actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('تمام'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    final changed = list == null ? 0 : _changed.length;
    final missing = list == null ? 0 : list.where(_empty).length;
    final shown = list
        ?.where((it) => !emptyOnly || _empty(it))
        .where((it) {
          final t = q.trim().toLowerCase();
          return t.isEmpty || it.name.toLowerCase().contains(t) || it.code.toLowerCase().contains(t) || ctl[it.id!]!.text.toLowerCase().contains(t);
        })
        .toList();

    return PopScope(
      canPop: changed == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await confirm(context, 'خروج من غير حفظ', 'في $changed اسم اتغير ولسه ما اتحفظش. تخرج برضو؟', ok: 'اخرج', danger: true)) nav.pop();
      },
      child: PageScaffold(
        title: 'أسماء الأصناف بالعربي',
        actions: [
          FilledButton.icon(
            onPressed: changed == 0 || saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(changed == 0 ? 'حفظ' : 'حفظ ($changed)'),
          ),
        ],
        body: list == null
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('طريقة العرض:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const NameModePicker(),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: isWide(context) ? 320 : double.infinity,
                      child: SearchField(hint: 'بحث بالاسم أو الكود...', onChanged: (v) => setState(() => q = v)),
                    ),
                    FilterChip(label: Text('بدون اسم عربي ($missing)'), selected: emptyOnly, onSelected: (v) => setState(() => emptyOnly = v)),
                    OutlinedButton.icon(onPressed: missing == 0 ? null : _suggest, icon: const Icon(Icons.auto_fix_high), label: const Text('اقتراح للفاضيين')),
                  ]),
                ),
                Expanded(
                  child: shown!.isEmpty
                      ? const EmptyView('مفيش أصناف', icon: Icons.inventory_2_outlined)
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                          ListCard(children: [for (final it in shown) _row(it)]),
                        ]),
                ),
              ]),
      ),
    );
  }

  Widget _row(Item it) {
    final c = ctl[it.id!]!;
    final edited = c.text.trim() != it.nameAr.trim();
    final arabicOriginal = ArabicNames.isArabic(it.name);
    final english = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(it.name, textDirection: arabicOriginal ? TextDirection.rtl : TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text([if (it.code.isNotEmpty && !it.name.contains(it.code)) it.code, it.unit].join('  •  '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
    final field = TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: arabicOriginal ? 'الاسم الأصلي عربي (اختياري)' : 'اكتب الاسم بالعربي',
        filled: true,
        fillColor: edited ? const Color(0xFFFFF8E1) : (c.text.trim().isEmpty && !arabicOriginal ? const Color(0xFFFFF1F0) : Colors.white),
        suffixIcon: IconButton(
          tooltip: 'اقتراح',
          icon: const Icon(Icons.auto_fix_high, size: 20),
          onPressed: () {
            final s = ArabicNames.suggest(it.name);
            if (s.isEmpty) return snack(context, 'مش لاقي اقتراح للصنف ده، اكتبه بإيدك');
            c.text = s;
          },
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: isWide(context)
          ? Row(children: [
              Expanded(flex: 5, child: english),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_back, size: 18, color: Colors.black38),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: field),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [english, const SizedBox(height: 8), field]),
    );
  }
}

/// Settings card: display mode + link to the review screen.
class ItemNamesCard extends StatelessWidget {
  const ItemNamesCard({super.key});

  @override
  Widget build(BuildContext context) => ListCard(title: 'أسماء الأصناف', children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الأصناف تظهر في البرنامج والطباعة إزاي:', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            const NameModePicker(),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.translate, color: kIn),
          title: const Text('مراجعة الأسماء بالعربي'),
          subtitle: const Text('كل اسم إنجليزي وقصاده العربي، تعدل أي واحد'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemNamesPage())),
        ),
      ]);
}
