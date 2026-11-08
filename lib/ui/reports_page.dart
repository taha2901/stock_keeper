import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../cubits/list_cubits.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'export_menu.dart';
import 'item_ledger_page.dart';
import 'voucher_view_page.dart';
import 'widgets.dart';

const _muted = TextStyle(fontSize: 12, color: Colors.black54);

double _sum<T>(Iterable<T> l, double Function(T) f) => l.fold(0.0, (a, x) => a + f(x));

/// Reports: inbound and outbound are always grouped by item (each item opens to its
/// movements); supplier / site / recipient are filters. The balance report shows,
/// per item, opening + receipts - issues = closing, with names, prices and values.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  ExportData? _export(ReportsCubit c, ReportData? d) {
    if (d == null) return null;
    final sub = [
      c.range == null ? 'كل التواريخ' : 'من ${fmtDate(c.range!.start)} إلى ${fmtDate(c.range!.end)}',
      if (c.party != null) c.party!.name,
      if (c.recipient != null) 'المستلم: ${c.recipient!.name}',
      if (c.ref.trim().isNotEmpty) 'رقم: ${c.ref.trim()}',
      if (c.q.trim().isNotEmpty) 'بحث: ${c.q.trim()}',
    ].join(' - ');

    if (c.mode == ReportMode.balance) {
      final b = d.balances;
      const h = [
        'الصنف', 'الكود', 'الوحدة', 'أول المدة', 'قيمة أول المدة', 'الوارد', 'قيمة الوارد', 'متوسط سعر الوارد',
        'الصادر', 'قيمة الصادر', 'آخر المدة', 'قيمة آخر المدة', 'المتبقي بالأسعار',
      ];
      return ExportData(title: c.mode.title, subtitle: sub, headers: h, rows: [
        for (final x in b)
          [
            x.item.label, x.item.code, x.item.unit, x.opening, x.openingValue, x.inQty, x.inValue, avgOf(x.ins),
            x.outQty, x.outValue, x.closing, x.closingValue, priceLabel(x.left),
          ],
        [
          'الإجمالي', null, null, null, _sum(b, (x) => x.openingValue), null, _sum(b, (x) => x.inValue), null,
          null, _sum(b, (x) => x.outValue), null, _sum(b, (x) => x.closingValue), null,
        ],
      ]);
    }
    final isIn = c.mode == ReportMode.inbound;
    final groups = groupMoves(d.moves);
    final h = ['الصنف', 'الكود', 'الوحدة', isIn ? 'إجمالي الوارد' : 'إجمالي الصادر', 'متوسط السعر', 'القيمة', 'عدد المرات', isIn ? 'آخر توريد' : 'آخر صرف'];
    return ExportData(title: c.mode.title, subtitle: sub, headers: h, rows: [
      for (final g in groups) [g.item.label, g.item.code, g.unit, g.total, g.avgPrice, g.value, g.times, g.last],
      ['الإجمالي', null, null, null, null, _sum(groups, (g) => g.value), null, null],
    ]);
  }

  Future<Party?> _pick(BuildContext context, PartyType t) => pickFrom<Party>(
        context,
        title: 'اختار ${t.label}',
        load: (q) => Repo.i.parties([t], q: q),
        label: (p) => p.name,
        sub: (p) => p.phone,
      );

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => ReportsCubit(),
        child: BlocBuilder<ReportsCubit, Load<ReportData>>(builder: (context, s) {
          final c = context.read<ReportsCubit>();
          final d = s.data;
          final isIn = c.mode == ReportMode.inbound;
          final fw = isWide(context) ? 260.0 : double.infinity;

          Widget partyChip(IconData icon, String all, Party? value, PartyType t, ValueChanged<Party?> set) => InputChip(
                avatar: Icon(icon, size: 18),
                label: Text(value?.name ?? all),
                onPressed: () async {
                  final p = await _pick(context, t);
                  if (p != null) set(p);
                },
                onDeleted: value == null ? null : () => set(null),
              );

          final header = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<ReportMode>(
                  showSelectedIcon: false,
                  segments: [for (final m in ReportMode.values) ButtonSegment(value: m, label: Text(m.label))],
                  selected: {c.mode},
                  onSelectionChanged: (v) => c.setMode(v.first),
                ),
                DateRangeChip(value: c.range, onChanged: c.setRange),
                if (c.singleType)
                  partyChip(
                    isIn ? Icons.local_shipping_outlined : Icons.location_on_outlined,
                    isIn ? 'كل الموردين' : 'كل المواقع',
                    c.party,
                    isIn ? PartyType.supplier : PartyType.site,
                    c.setParty,
                  ),
                if (c.mode == ReportMode.outbound) partyChip(Icons.person_outline, 'كل المستلمين', c.recipient, PartyType.recipient, c.setRecipient),
                SizedBox(width: fw, child: SearchField(hint: 'بحث بالصنف...', onChanged: c.search)),
                if (c.singleType)
                  SizedBox(
                    width: fw,
                    child: TextField(
                      key: ValueKey(c.mode),
                      onChanged: c.setRef,
                      decoration: InputDecoration(
                        hintText: isIn ? 'رقم الفاتورة...' : 'الرقم المرجعي...',
                        prefixIcon: const Icon(Icons.receipt_long_outlined),
                      ),
                    ),
                  ),
              ]),
            ),
            if (d != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: _Summary(c, d)),
          ];

          Widget body() {
            if (d == null) return const Center(child: CircularProgressIndicator());
            if (c.mode == ReportMode.balance) {
              final rows = d.balances;
              if (rows.isEmpty) return const EmptyView('مفيش أصناف في الفترة دي', icon: Icons.inventory_2_outlined);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _BalanceCard(rows[i]),
              );
            }
            final groups = groupMoves(d.moves);
            if (groups.isEmpty) return const EmptyView('مفيش حركات بالفلتر ده', icon: Icons.bar_chart_rounded);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _GroupCard(groups[i], isIn),
            );
          }

          return PageScaffold(
            title: c.mode.title,
            actions: [ExportMenu(data: _export(c, d))],
            body: Column(children: [...header, Expanded(child: body())]),
          );
        }),
      );
}

// ---------------- summary tiles ----------------

class _Summary extends StatelessWidget {
  const _Summary(this.c, this.d);
  final ReportsCubit c;
  final ReportData d;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    if (c.mode == ReportMode.balance) {
      final b = d.balances;
      final missing = b.any((x) => x.missing);
      tiles.addAll([
        _Kpi('الأصناف', '${b.length}', Icons.inventory_2_outlined, Colors.indigo),
        _Kpi('قيمة أول المدة', fmtMoney(_sum(b, (x) => x.openingValue)), Icons.history, Colors.blueGrey),
        _Kpi('قيمة الوارد', fmtMoney(_sum(b, (x) => x.inValue)), typeIcon(VType.inbound), kIn),
        _Kpi('قيمة الصادر', fmtMoney(_sum(b, (x) => x.outValue)), typeIcon(VType.outbound), kOut),
        _Kpi('قيمة آخر المدة', valueLabel(_sum(b, (x) => x.closingValue), missing), Icons.account_balance_wallet_outlined, Colors.teal, strong: true),
      ]);
    } else {
      final isIn = c.mode == ReportMode.inbound;
      final m = d.moves;
      final missing = m.where((r) => r.cost.missing).length;
      final color = isIn ? kIn : kOut;
      tiles.addAll([
        _Kpi('الأصناف', '${m.map((r) => r.itemId).toSet().length}', Icons.inventory_2_outlined, Colors.indigo),
        _Kpi(isIn ? 'سندات الاستلام' : 'أذون الصرف', '${m.map((r) => r.voucherId).toSet().length}', Icons.receipt_long_outlined, Colors.blueGrey),
        _Kpi(isIn ? 'قيمة الوارد' : 'قيمة الصادر', valueLabel(_sum(m, (r) => r.cost.value), missing > 0), isIn ? typeIcon(VType.inbound) : typeIcon(VType.outbound), color,
            strong: true),
        if (missing > 0) _Kpi('بنود بدون سعر', '$missing', Icons.error_outline, kOut),
      ]);
    }
    return Align(alignment: AlignmentDirectional.centerStart, child: Wrap(spacing: 8, runSpacing: 8, children: tiles));
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color, {this.strong = false});
  final String label, value;
  final IconData icon;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: strong ? color.withValues(alpha: .10) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: strong ? color.withValues(alpha: .35) : kLine),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: _muted),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: strong ? color : null)),
          ]),
        ]),
      );
}

// ---------------- inbound / outbound, by item ----------------

class _GroupCard extends StatelessWidget {
  const _GroupCard(this.g, this.isIn);
  final GroupRow g;
  final bool isIn;

  @override
  Widget build(BuildContext context) {
    final color = isIn ? kIn : kOut;
    final avg = g.avgPrice;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
        childrenPadding: EdgeInsets.zero,
        title: Text(g.item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            if (g.item.extra.isNotEmpty) Text(g.item.extra, style: _muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            _Pill('${g.times} ${g.times == 1 ? 'مرة' : 'مرات'}'),
            _Pill('${isIn ? 'آخر توريد' : 'آخر صرف'} ${fmtDate(g.last)}'),
            if (avg != null) _Pill('متوسط السعر ${fmtMoney(avg)}'),
          ]),
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtQty(g.total)} ${g.unit}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          Text('${valueLabel(g.value, g.missing)} ريال', style: _muted),
        ]),
        children: [
          const Divider(),
          for (final r in g.moves.reversed) _MoveTile(r),
        ],
      ),
    );
  }
}

/// One receipt / issue line: who, when, which document, quantity, price and value.
class _MoveTile extends StatelessWidget {
  const _MoveTile(this.r);
  final MovementRow r;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(r.type);
    final price = priceLabel(r.cost, sep: '  +  ');
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(r.isTransfer ? Icons.swap_horiz : typeIcon(r.type), size: 16, color: color),
      ),
      title: Text(r.who.isEmpty ? '-' : r.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          [
            fmtDate(r.date),
            '${r.type.doc} ${r.number}',
            if (r.refNo.isNotEmpty) '${r.type.isIn ? 'فاتورة' : 'مرجع'} ${r.refNo}',
            if (r.recipient.isNotEmpty) 'المستلم: ${r.recipient}',
          ].join('  •  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (price.isNotEmpty)
          Text('السعر: $price', style: TextStyle(fontSize: 12, color: r.cost.missing ? kOut : Colors.black87, fontWeight: FontWeight.w600)),
      ]),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${r.type.isIn ? '+' : '-'}${fmtQty(r.qty)} ${r.unit}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        Text(valueLabel(r.cost.value, r.cost.missing), style: _muted),
      ]),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherViewPage(id: r.voucherId))),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: (color ?? Colors.blueGrey).withValues(alpha: .09), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color ?? Colors.black87)),
      );
}

// ---------------- balance: opening + in - out = closing ----------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.b);
  final BalanceRow b;

  @override
  Widget build(BuildContext context) {
    final it = b.item;
    final neg = b.closing < 0;
    final ins = b.ins.toList(), outs = b.outs.toList();
    final avgIn = avgOf(ins), avgOut = avgOf(outs);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
        childrenPadding: EdgeInsets.zero,
        title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (it.extra.isNotEmpty) Text(it.extra, style: _muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${fmtQty(b.closing)} ${it.unit}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: neg ? Colors.red : null)),
            Text('${valueLabel(b.closingValue, b.missing)} ريال', style: _muted),
          ]),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _Flow(b),
        ),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (avgIn != null) _Pill('متوسط سعر الوارد ${fmtMoney(avgIn)}', color: kIn),
              if (avgOut != null) _Pill('متوسط تكلفة الصادر ${fmtMoney(avgOut)}', color: kOut),
              if (b.left.slices.isNotEmpty) _Pill('المتبقي بالأسعار: ${priceLabel(b.left, sep: '  +  ')}', color: Colors.teal),
              if (neg) const _Pill('الرصيد بالسالب: فيه صرف قبل الاستلام اللي يغطيه', color: Colors.red),
            ]),
          ),
          _Section('الوارد في الفترة', ins, kIn),
          _Section('الصادر في الفترة', outs, kOut),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('كارت الصنف'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemLedgerPage(stock: ItemStock(it, b.inQty, b.outQty)))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// أول المدة + الوارد − الصادر = آخر المدة, each with quantity and value.
class _Flow extends StatelessWidget {
  const _Flow(this.b);
  final BalanceRow b;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double qty, double value, Color color, {bool strong = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: strong ? .12 : .06), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(fmtQty(qty), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(fmtMoney(value), style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ),
            ]),
          ),
        );
    Widget op(String s) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black38)),
        );
    return Row(children: [
      cell('أول المدة', b.opening, b.openingValue, Colors.blueGrey),
      op('+'),
      cell('الوارد', b.inQty, b.inValue, kIn),
      op('−'),
      cell('الصادر', b.outQty, b.outValue, kOut),
      op('='),
      cell('آخر المدة', b.closing, b.closingValue, b.closing < 0 ? Colors.red : Colors.teal, strong: true),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows, this.color);
  final String title;
  final List<MovementRow> rows;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Row(children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text('$title (${rows.length})', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            const Spacer(),
            if (rows.isNotEmpty)
              Text('${fmtQty(_sum(rows, (r) => r.qty))}  •  ${valueLabel(_sum(rows, (r) => r.cost.value), rows.any((r) => r.cost.missing))} ريال',
                  style: _muted),
          ]),
        ),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(28, 4, 16, 6), child: Text('مفيش', style: _muted))
        else
          for (final r in rows) _MoveTile(r),
      ]);
}
