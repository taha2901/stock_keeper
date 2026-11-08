import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/list_cubits.dart';
import '../data/models.dart';
import 'export_menu.dart';
import 'widgets.dart';

/// Suppliers / sites / recipients in three tabs.
class PartiesPage extends StatelessWidget {
  const PartiesPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: PartyType.values.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الموردين والمواقع'),
            bottom: TabBar(tabs: [for (final t in PartyType.values) Tab(text: t.plural)]),
          ),
          body: TabBarView(children: [for (final t in PartyType.values) _PartyList(t)]),
        ),
      );
}

class _PartyList extends StatelessWidget {
  const _PartyList(this.type);
  final PartyType type;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => PartiesCubit(type),
        child: BlocBuilder<PartiesCubit, Load<List<Party>>>(builder: (context, s) {
          final list = s.data;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: SearchField(hint: 'بحث...', onChanged: context.read<PartiesCubit>().search)),
                  ExportMenu(
                    data: list == null
                        ? null
                        : ExportData(
                            title: 'قائمة ${type.plural}',
                            headers: const ['الاسم', 'رقم التليفون'],
                            rows: [for (final p in list) [p.name, p.phone]],
                          ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: () => partyDialog(context, type), icon: const Icon(Icons.add), label: Text('إضافة ${type.label}')),
                ]),
                const SizedBox(height: 12),
                if (list == null)
                  const Center(child: CircularProgressIndicator())
                else if (list.isEmpty)
                  EmptyView('مفيش ${type.plural} لسه', icon: Icons.groups_outlined)
                else
                  ListCard(children: [
                    for (final p in list)
                      ListTile(
                        leading: CircleAvatar(child: Text(p.name.characters.first)),
                        title: Text(p.name),
                        subtitle: p.phone.isEmpty ? null : Text(p.phone),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => partyDialog(context, type, party: p),
                      ),
                  ]),
              ]),
            ),
          );
        }),
      );
}
