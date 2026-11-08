import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../cubits/list_cubits.dart';
import '../data/models.dart';
import 'item_ledger_page.dart';
import 'transfer_page.dart';
import 'voucher_form_page.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNav});
  final ValueChanged<int> onNav;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => HomeCubit(),
        child: PageScaffold(
          title: 'الرئيسية',
          actions: [Center(child: Text(fmtDate(DateTime.now()), style: const TextStyle(color: Colors.black54)))],
          body: BlocBuilder<HomeCubit, Load<HomeStats>>(builder: (context, s) {
            final d = s.data;
            if (d == null) return const Center(child: CircularProgressIndicator());
            final wide = isWide(context);
            final w = MediaQuery.sizeOf(context).width;
            final statW = wide ? 250.0 : (w - 44) / 2;

            final recent = ListCard(
              title: 'آخر الحركات',
              children: d.recent.isEmpty ? [const EmptyView('لسه مفيش حركات')] : [for (final v in d.recent) VoucherTile(v)],
            );
            final low = ListCard(
              title: 'أصناف قربت تخلص',
              children: d.low.isEmpty
                  ? [const EmptyView('كل الأصناف تمام', icon: Icons.check_circle_outline)]
                  : [
                      for (final it in d.low.take(8))
                        ListTile(
                          leading: const Icon(Icons.warning_amber_rounded, color: kOut),
                          title: Text(it.item.title),
                          trailing: Text('${fmtQty(it.balance)} ${it.item.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: kOut)),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemLedgerPage(stock: it))),
                        ),
                    ],
            );

            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: _Action(VType.inbound, 'سند استلام', 'تسجيل بضاعة واردة')),
                const SizedBox(width: 12),
                Expanded(child: _Action(VType.outbound, 'إذن صرف', 'تسجيل صرف لموقع')),
              ]),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFF4A5568),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferPage())),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.swap_horiz, color: Colors.white)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('تحويل بين المخازن', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      Icon(Icons.chevron_left, color: Colors.white70),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: statW, child: StatCard(label: 'الأصناف', value: '${d.items}', icon: Icons.inventory_2_outlined, color: Colors.indigo, onTap: () => onNav(3))),
                SizedBox(width: statW, child: StatCard(label: 'وارد النهارده', value: '${d.todayIn}', icon: typeIcon(VType.inbound), color: kIn, onTap: () => onNav(1))),
                SizedBox(width: statW, child: StatCard(label: 'صادر النهارده', value: '${d.todayOut}', icon: typeIcon(VType.outbound), color: kOut, onTap: () => onNav(2))),
                SizedBox(width: statW, child: StatCard(label: 'قيمة المخزون (ريال)', value: fmtMoney(d.stockValue), icon: Icons.payments_outlined, color: Colors.teal, onTap: () => onNav(3))),
                SizedBox(width: statW, child: StatCard(label: 'نواقص', value: '${d.low.length}', icon: Icons.warning_amber_rounded, color: Colors.red, onTap: () => onNav(3))),
              ]),
              const SizedBox(height: 12),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: recent),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: low),
                ])
              else ...[recent, const SizedBox(height: 12), low],
            ]);
          }),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action(this.type, this.title, this.sub);
  final VType type;
  final String title, sub;

  @override
  Widget build(BuildContext context) {
    final c = typeColor(type);
    return Material(
      color: c,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openVoucherForm(context, type),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.add, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
