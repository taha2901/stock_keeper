import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../cubits/list_cubits.dart';
import '../data/models.dart';
import 'export_menu.dart';
import 'import_vouchers.dart';
import 'voucher_form_page.dart';
import 'widgets.dart';

class VouchersPage extends StatelessWidget {
  const VouchersPage({super.key, required this.type});
  final VType type;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => VouchersCubit(type),
        child: Builder(builder: (context) {
          final cubit = context.read<VouchersCubit>();
          return PageScaffold(
            title: type.isIn ? 'الوارد - سندات الاستلام' : 'الصادر - أذونات الصرف',
            actions: [
              if (type.isIn)
                PopupMenuButton<String>(
                  tooltip: 'استيراد من ملف',
                  onSelected: (v) => v == 'import' ? importInboundFlow(context) : downloadImportTemplate(context),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.upload_file, size: 20), SizedBox(width: 10), Text('استيراد وارد من Excel')])),
                    const PopupMenuItem(value: 'template', child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 10), Text('تحميل نموذج الاستيراد')])),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.upload_file), SizedBox(width: 4), Text('استيراد')]),
                  ),
                ),
              BlocBuilder<VouchersCubit, Load<List<Voucher>>>(
                builder: (_, s) => ExportMenu(
                  data: s.data == null
                      ? null
                      : ExportData(
                          title: type.isIn ? 'سندات الاستلام' : 'أذونات الصرف',
                          subtitle: cubit.range == null ? '' : 'من ${fmtDate(cubit.range!.start)} إلى ${fmtDate(cubit.range!.end)}',
                          headers: [
                            'الرقم', 'المخزن', 'التاريخ', type.partyType.label,
                            if (!type.isIn) 'المستلم',
                            type.isIn ? 'رقم الفاتورة' : 'رقم مرجعي', 'رقم الرخصة', 'عدد الأصناف', 'القيمة', 'ملاحظات',
                          ],
                          rows: [
                            for (final v in s.data!)
                              [v.number, v.warehouseName, v.date, v.partyName, if (!type.isIn) v.recipientName, v.refNo, v.licenseNo, v.lineCount, v.total, v.notes],
                          ],
                        ),
                ),
              ),
            ],
            fab: FloatingActionButton.extended(
              onPressed: () => openVoucherForm(context, type),
              icon: const Icon(Icons.add),
              label: Text('${type.doc} جديد'),
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: isWide(context) ? 380 : double.infinity,
                    child: SearchField(hint: 'بحث برقم السند، الصنف، ${type.partyType.label}...', onChanged: cubit.search),
                  ),
                  BlocBuilder<VouchersCubit, Load<List<Voucher>>>(
                    builder: (_, _) => DateRangeChip(value: cubit.range, onChanged: cubit.setRange),
                  ),
                ]),
              ),
              Expanded(
                child: BlocBuilder<VouchersCubit, Load<List<Voucher>>>(builder: (_, s) {
                  final list = s.data;
                  if (list == null) return const Center(child: CircularProgressIndicator());
                  if (list.isEmpty) return EmptyView('مفيش ${type.isIn ? 'سندات استلام' : 'أذونات صرف'}\nدوس «${type.doc} جديد» عشان تبدأ');
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: [ListCard(children: [for (final v in list) VoucherTile(v)])],
                  );
                }),
              ),
            ]),
          );
        }),
      );
}
