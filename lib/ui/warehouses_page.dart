import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import 'transfer_page.dart';
import 'widgets.dart';

/// Add / rename / delete warehouses, and pick the one the app is showing.
class WarehousesPage extends StatefulWidget {
  const WarehousesPage({super.key});
  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  late Future<List<Warehouse>> f = Repo.i.warehouses();

  void _reload() => setState(() => f = Repo.i.warehouses());

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'المخازن',
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferPage())),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('تحويل'),
          ),
        ],
        fab: FloatingActionButton.extended(
          onPressed: () async {
            if (await warehouseDialog(context) != null) _reload();
          },
          icon: const Icon(Icons.add),
          label: const Text('مخزن جديد'),
        ),
        body: FutureBuilder<List<Warehouse>>(
          future: f,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(16), children: [
              ListCard(children: [
                for (final w in list)
                  ListTile(
                    leading: Icon(Icons.warehouse_outlined,
                        color: w.id == Repo.i.currentWarehouseId ? Theme.of(context).colorScheme.primary : null),
                    title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: w.id == Repo.i.currentWarehouseId ? const Text('المخزن الحالي') : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (w.id != Repo.i.currentWarehouseId)
                        TextButton(
                          onPressed: () async {
                            await Repo.i.setCurrentWarehouse(w.id!);
                            _reload();
                          },
                          child: const Text('اختيار'),
                        ),
                      IconButton(
                        tooltip: 'تعديل',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () async {
                          if (await warehouseDialog(context, warehouse: w) != null) _reload();
                        },
                      ),
                      IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        onPressed: () async {
                          if (!await confirm(context, 'مسح المخزن', 'تمسح «${w.name}»؟', ok: 'مسح', danger: true)) return;
                          try {
                            await Repo.i.deleteWarehouse(w.id!);
                            _reload();
                          } catch (e) {
                            if (context.mounted) snack(context, '\$e', error: true);
                          }
                        },
                      ),
                    ]),
                  ),
              ]),
            ]);
          },
        ),
      );
}

Future<Warehouse?> warehouseDialog(BuildContext context, {Warehouse? warehouse, String name = ''}) =>
    showDialog<Warehouse>(context: context, builder: (_) => _WarehouseDialog(warehouse, name));

class _WarehouseDialog extends StatefulWidget {
  const _WarehouseDialog(this.warehouse, this.initialName);
  final Warehouse? warehouse;
  final String initialName;
  @override
  State<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends State<_WarehouseDialog> {
  late final name = TextEditingController(text: widget.warehouse?.name ?? widget.initialName);
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
        title: Text(widget.warehouse == null ? 'مخزن جديد' : 'تعديل المخزن'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المخزن *')),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
        actions: [
          if (widget.warehouse != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => _run(() async {
                if (!await confirm(context, 'مسح المخزن', 'تمسح «${widget.warehouse!.name}»؟', ok: 'مسح', danger: true)) return;
                await Repo.i.deleteWarehouse(widget.warehouse!.id!);
                if (context.mounted) Navigator.pop(context, widget.warehouse);
              }),
              child: const Text('مسح'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => _run(() async {
              if (name.text.trim().isEmpty) throw 'اكتب اسم المخزن';
              final w = await Repo.i.saveWarehouse(Warehouse(id: widget.warehouse?.id, name: name.text));
              if (context.mounted) Navigator.pop(context, w);
            }),
            child: const Text('حفظ'),
          ),
        ],
      );
}

/// Picker used on the voucher form to choose which warehouse the voucher is for.
Future<Warehouse?> pickWarehouse(BuildContext context) => pickFrom<Warehouse>(
      context,
      title: 'اختار المخزن',
      load: (q) async {
        final all = await Repo.i.warehouses();
        return q.trim().isEmpty ? all : all.where((w) => w.name.contains(q.trim())).toList();
      },
      label: (w) => w.name,
      addLabel: 'مخزن جديد',
      onAdd: (q) => warehouseDialog(context, name: q),
    );
