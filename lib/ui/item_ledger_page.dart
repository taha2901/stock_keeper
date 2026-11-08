import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../cubits/list_cubits.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'export_menu.dart';
import 'voucher_view_page.dart';
import 'widgets.dart';

/// "كارت الصنف": every movement of one item with the running balance.
class ItemLedgerPage extends StatelessWidget {
  const ItemLedgerPage({super.key, required this.stock, this.warehouseId});
  final ItemStock stock;
  final int? warehouseId;

  @override
  Widget build(BuildContext context) {
    final it = stock.item;
    return BlocProvider(
      create: (_) => LedgerCubit(it.id!, warehouseId ?? Repo.i.currentWarehouseId),
      child: BlocBuilder<LedgerCubit, Load<List<LedgerRow>>>(builder: (context, s) {
        final rows = s.data;
        final bal = rows == null || rows.isEmpty ? 0.0 : rows.first.balance;
        final inQ = rows?.where((r) => r.type.isIn).fold(0.0, (a, r) => a + r.qty) ?? 0;
        final outQ = rows?.where((r) => !r.type.isIn).fold(0.0, (a, r) => a + r.qty) ?? 0;
        final w = isWide(context) ? 240.0 : double.infinity;
        final stockValue = rows == null || rows.isEmpty ? 0.0 : rows.first.stockValue;
        final anyMissing = rows?.any((r) => r.cost.missing) ?? false;
        return PageScaffold(
          title: 'كارت الصنف',
          actions: [
            ExportMenu(
              data: rows == null
                  ? null
                  : ExportData(
                      title: 'كارت صنف - ${it.name}',
                      subtitle: 'الوحدة: ${it.unit} - الرصيد الحالي: ${fmtQty(bal)}',
                      headers: const ['التاريخ', 'النوع', 'رقم السند', 'الجهة', 'رقم الفاتورة', 'وارد', 'صادر', 'الرصيد', 'السعر', 'القيمة', 'قيمة الرصيد'],
                      rows: [
                        for (final r in rows.reversed)
                          [r.date, r.type.label, r.number, r.party, r.refNo, r.type.isIn ? r.qty : null, r.type.isIn ? null : r.qty, r.balance, priceLabel(r.cost), r.cost.value, r.stockValue],
                      ],
                    ),
            ),
          ],
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(it.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                subtitle: it.extra.isEmpty ? null : Text(it.extra),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: w, child: StatCard(label: 'الرصيد الحالي (${it.unit})', value: fmtQty(bal), icon: Icons.inventory_2_outlined, color: bal < 0 ? Colors.red : Colors.indigo)),
              SizedBox(width: w, child: StatCard(label: 'قيمة الرصيد (ريال)', value: valueLabel(stockValue, anyMissing), icon: Icons.payments_outlined, color: Colors.teal)),
              SizedBox(width: w, child: StatCard(label: 'إجمالي الوارد', value: fmtQty(inQ), icon: typeIcon(VType.inbound), color: kIn)),
              SizedBox(width: w, child: StatCard(label: 'إجمالي الصادر', value: fmtQty(outQ), icon: typeIcon(VType.outbound), color: kOut)),
            ]),
            const SizedBox(height: 12),
            ListCard(title: 'الحركات', children: [
              if (rows == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (rows != null && rows.isEmpty) const EmptyView('مفيش حركات على الصنف ده'),
              for (final r in rows ?? <LedgerRow>[])
                ListTile(
                  leading: TypeBadge(r.type),
                  title: Text('${r.type.doc} ${r.number}  •  ${r.party.isEmpty ? '-' : r.party}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([fmtDate(r.date), if (r.refNo.isNotEmpty) 'فاتورة ${r.refNo}', priceLabel(r.cost, sep: '  +  ')].join('  •  ')),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${r.type.isIn ? '+' : '-'}${fmtQty(r.qty)}', style: TextStyle(fontWeight: FontWeight.w800, color: typeColor(r.type))),
                    Text('${valueLabel(r.cost.value, r.cost.missing)}  •  الرصيد ${fmtQty(r.balance)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherViewPage(id: r.voucherId))),
                ),
            ]),
          ]),
        );
      }),
    );
  }
}
