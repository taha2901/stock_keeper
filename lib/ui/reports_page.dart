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

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  double _sum<T>(Iterable<T> l, double Function(T) f) => l.fold(0.0, (a, x) => a + f(x));

  /// A last row carrying only the money total, placed under the value column.
  List<Object?> _totalRow(int columns, int valueCol, double total) => [
        for (var c = 0; c < columns; c++) c == 0 ? 'الإجمالي' : (c == valueCol ? total : null),
      ];

  ExportData? _export(ReportsCubit c, ReportData? d) {
    if (d == null) return null;
    final sub = [
      c.range == null ? 'كل التواريخ' : 'من ${fmtDate(c.range!.start)} إلى ${fmtDate(c.range!.end)}',
      if (c.party != null) c.party!.name,
      if (c.recipient != null) 'المستلم: ${c.recipient!.name}',
      if (c.ref.trim().isNotEmpty) 'رقم: ${c.ref.trim()}',
      if (c.q.trim().isNotEmpty) 'بحث: ${c.q.trim()}',
    ].join(' - ');
    final isIn = c.mode == ReportMode.inbound;
    final moves = d.moves;
    final value = _sum(moves, (r) => r.cost.value);

    if (c.mode == ReportMode.balance) {
      const h = ['الصنف', 'الوحدة', 'أول المدة', 'قيمة أول المدة', 'الوارد', 'قيمة الوارد', 'الصادر', 'قيمة الصادر', 'آخر المدة', 'قيمة آخر المدة'];
      return ExportData(title: c.mode.title, subtitle: sub, headers: h, rows: [
        for (final b in d.balances) [b.item.name, b.item.unit, b.opening, b.openingValue, b.inQty, b.inValue, b.outQty, b.outValue, b.closing, b.closingValue],
        [
          'الإجمالي', null, null, _sum(d.balances, (b) => b.openingValue), null, _sum(d.balances, (b) => b.inValue),
          null, _sum(d.balances, (b) => b.outValue), null, _sum(d.balances, (b) => b.closingValue),
        ],
      ]);
    }
    if (c.activeView == ReportView.item) {
      final h = ['الصنف', 'الوحدة', isIn ? 'إجمالي الوارد' : 'إجمالي الصادر', 'القيمة', 'عدد المرات', isIn ? 'آخر توريد' : 'آخر صرف'];
      return ExportData(title: '${c.mode.title} - بالصنف', subtitle: sub, headers: h, rows: [
        for (final g in groupMoves(moves)) [g.item, g.unit, g.total, g.value, g.times, g.last],
        _totalRow(h.length, 3, value),
      ]);
    }
    if (c.activeView == ReportView.party) {
      final h = [isIn ? 'المورد' : 'الموقع', 'عدد السندات', 'عدد البنود', 'القيمة'];
      return ExportData(title: '${c.mode.title} - ${isIn ? 'بالمورد' : 'بالموقع'}', subtitle: sub, headers: h, rows: [
        for (final g in groupParties(moves)) [g.party, g.vouchers, g.lines, g.value],
        _totalRow(h.length, 3, value),
      ]);
    }
    final h = [
      'التاريخ', 'رقم السند', isIn ? 'رقم الفاتورة' : 'رقم مرجعي', 'الصنف', 'الوحدة', 'الكمية', 'السعر', 'القيمة',
      isIn ? 'المورد' : 'الموقع',
      if (!isIn) 'المستلم',
    ];
    return ExportData(title: c.mode.title, subtitle: sub, headers: h, rows: [
      for (final r in moves) [r.date, r.number, r.refNo, r.item, r.unit, r.qty, priceLabel(r.cost), r.cost.value, r.party, if (!isIn) r.recipient],
      _totalRow(h.length, 7, value),
    ]);
  }

  Future<Party?> _pick(BuildContext context, PartyType t) => pickFrom<Party>(
        context,
        title: 'اختار ${t.label}',
        load: (q) => Repo.i.parties([t], q: q),
        label: (p) => p.name,
        sub: (p) => p.phone,
      );

  Widget _summary(ReportsCubit c, ReportData d) {
    const bold = TextStyle(fontWeight: FontWeight.w700);
    if (c.mode == ReportMode.balance) {
      final missing = d.balances.any((b) => b.missing);
      return Wrap(spacing: 16, children: [
        Text('${d.balances.length} صنف', style: bold),
        Text('قيمة الوارد ${fmtMoney(_sum(d.balances, (b) => b.inValue))}', style: const TextStyle(color: kIn)),
        Text('قيمة الصادر ${fmtMoney(_sum(d.balances, (b) => b.outValue))}', style: const TextStyle(color: kOut)),
        Text('قيمة آخر المدة ${valueLabel(_sum(d.balances, (b) => b.closingValue), missing)}', style: bold),
      ]);
    }
    final moves = d.moves;
    final inV = _sum(moves.where((r) => r.type.isIn), (r) => r.cost.value);
    final outV = _sum(moves.where((r) => !r.type.isIn), (r) => r.cost.value);
    final missing = moves.where((r) => r.cost.missing).length;
    return Wrap(spacing: 16, children: [
      Text('${moves.length} حركة', style: bold),
      if (c.mode != ReportMode.outbound) Text('قيمة الوارد ${fmtMoney(inV)}', style: const TextStyle(color: kIn, fontWeight: FontWeight.w700)),
      if (c.mode != ReportMode.inbound) Text('قيمة الصادر ${fmtMoney(outV)}', style: const TextStyle(color: kOut, fontWeight: FontWeight.w700)),
      if (missing > 0) Text('* $missing بند بدون سعر (مش داخل في الإجمالي)', style: const TextStyle(color: kOut)),
    ]);
  }

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

          Widget content() {
            if (c.mode == ReportMode.balance) return _balances(context, d!.balances);
            return switch (c.activeView) {
              ReportView.item => _groups(groupMoves(d!.moves), isIn),
              ReportView.party => _parties(groupParties(d!.moves), isIn),
              ReportView.detail => _moves(context, d!.moves),
            };
          }

          return PageScaffold(
            title: c.mode.title,
            actions: [ExportMenu(data: _export(c, d))],
            body: Column(children: [
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
                  if (c.singleType)
                    SegmentedButton<ReportView>(
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(value: ReportView.detail, label: Text('تفصيلي')),
                        const ButtonSegment(value: ReportView.item, label: Text('بالصنف')),
                        ButtonSegment(value: ReportView.party, label: Text(isIn ? 'بالمورد' : 'بالموقع')),
                      ],
                      selected: {c.view},
                      onSelectionChanged: (v) => c.setView(v.first),
                    ),
                ]),
              ),
              if (d != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: AlignmentDirectional.centerStart, child: _summary(c, d))),
              const SizedBox(height: 8),
              Expanded(child: d == null ? const Center(child: CircularProgressIndicator()) : content()),
            ]),
          );
        }),
      );

  Widget _trailing(String top, String bottom, Color? color) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(top, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        Text(bottom, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);

  Widget _list(List<Widget> tiles, String empty, IconData icon) => tiles.isEmpty
      ? EmptyView(empty, icon: icon)
      : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [ListCard(children: tiles)]);

  Widget _moves(BuildContext context, List<MovementRow> rows) => _list([
        for (final r in rows)
          ListTile(
            leading: TypeBadge(r.type),
            title: Text(r.item, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                [
                  fmtDate(r.date),
                  '${r.type.doc} ${r.number}',
                  if (r.refNo.isNotEmpty) r.refNo,
                  if (r.party.isNotEmpty) r.party,
                  if (r.recipient.isNotEmpty) r.recipient,
                  priceLabel(r.cost, sep: ' + '),
                ].join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: _trailing('${fmtQty(r.qty)} ${r.unit}', valueLabel(r.cost.value, r.cost.missing), typeColor(r.type)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherViewPage(id: r.voucherId))),
          ),
      ], 'مفيش حركات بالفلتر ده', Icons.bar_chart_rounded);

  Widget _groups(List<GroupRow> rows, bool isIn) => _list([
        for (final g in rows)
          ListTile(
            title: Text(g.item, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${g.times} مرة  •  ${isIn ? 'آخر توريد' : 'آخر صرف'} ${fmtDate(g.last)}'),
            trailing: _trailing('${fmtQty(g.total)} ${g.unit}', valueLabel(g.value, g.missing), isIn ? kIn : kOut),
          ),
      ], 'مفيش حركات بالفلتر ده', Icons.bar_chart_rounded);

  Widget _parties(List<PartyTotal> rows, bool isIn) => _list([
        for (final g in rows)
          ListTile(
            leading: Icon(isIn ? Icons.local_shipping_outlined : Icons.location_on_outlined),
            title: Text(g.party.isEmpty ? '-' : g.party, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${g.vouchers} سند  •  ${g.lines} بند'),
            trailing: Text('${valueLabel(g.value, g.missing)} ريال', style: TextStyle(fontWeight: FontWeight.w800, color: isIn ? kIn : kOut)),
          ),
      ], 'مفيش حركات بالفلتر ده', Icons.bar_chart_rounded);

  Widget _balances(BuildContext context, List<BalanceRow> rows) => _list([
        for (final b in rows)
          ListTile(
            title: Text(b.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('أول المدة ${fmtQty(b.opening)}  •  وارد ${fmtQty(b.inQty)}  •  صادر ${fmtQty(b.outQty)}'),
            trailing: _trailing('${fmtQty(b.closing)} ${b.item.unit}', valueLabel(b.closingValue, b.missing), b.closing < 0 ? Colors.red : null),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemLedgerPage(stock: ItemStock(b.item, b.inQty, b.outQty)))),
          ),
      ], 'مفيش أصناف', Icons.inventory_2_outlined);
}
