import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../cubits/list_cubits.dart';
import '../data/models.dart';
import 'export_menu.dart';
import 'item_ledger_page.dart';
import 'widgets.dart';

class StockPage extends StatelessWidget {
  const StockPage({super.key});

  ExportData? _export(List<ItemStock>? list) => list == null
      ? null
      : ExportData(
          title: 'أرصدة المخزون',
          headers: const ['الصنف', 'الكود', 'الوحدة', 'وارد', 'صادر', 'الرصيد', 'قيمة الرصيد', 'حد التنبيه'],
          rows: [
            for (final s in list) [s.item.name, s.item.code, s.item.unit, s.inQty, s.outQty, s.balance, s.value, s.item.minQty],
            ['الإجمالي', null, null, null, null, null, list.fold<double>(0.0, (a, s) => a + s.value), null],
          ],
        );

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => StockCubit(),
        child: BlocBuilder<StockCubit, Load<List<ItemStock>>>(builder: (context, s) {
          final cubit = context.read<StockCubit>();
          final list = s.data;
          return PageScaffold(
            title: 'المخزون والأرصدة',
            actions: [ExportMenu(data: _export(list))],
            fab: FloatingActionButton.extended(onPressed: () => itemDialog(context), icon: const Icon(Icons.add), label: const Text('صنف جديد')),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(child: SearchField(hint: 'بحث بالاسم أو الكود...', onChanged: cubit.search)),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('النواقص'), selected: cubit.lowOnly, onSelected: (_) => cubit.toggleLow()),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('كل الأصناف'), selected: cubit.allItems, onSelected: (_) => cubit.toggleAll()),
                ]),
              ),
              if (list != null && list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'قيمة المخزون: ${valueLabel(list.fold(0.0, (a, s) => a + s.value), list.any((s) => s.missing))} ريال',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Expanded(
                child: list == null
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? const EmptyView('مفيش أصناف\nالأصناف بتتضاف من «صنف جديد» أو وانت بتعمل سند استلام', icon: Icons.inventory_2_outlined)
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                            ListCard(children: [
                              for (final it in list)
                                ListTile(
                                  title: Text(it.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(it.item.extra.isEmpty ? 'وارد ${fmtQty(it.inQty)}  •  صادر ${fmtQty(it.outQty)}' : it.item.extra,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Text(fmtQty(it.balance),
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: it.low ? kOut : null)),
                                      Text('${it.item.unit}  •  ${valueLabel(it.value, it.missing)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    ]),
                                    IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => itemDialog(context, item: it.item)),
                                  ]),
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemLedgerPage(stock: it))),
                                ),
                            ]),
                          ]),
              ),
            ]),
          );
        }),
      );
}
