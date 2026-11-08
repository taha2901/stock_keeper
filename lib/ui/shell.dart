import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../cubits/voucher_form_cubit.dart';
import '../data/models.dart';
import '../services/backup_service.dart';
import '../services/daily_service.dart';
import '../data/repo.dart';
import '../services/license_service.dart';
import '../services/pdf_service.dart';
import 'activation_page.dart';
import 'home_page.dart';
import 'parties_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'stock_page.dart';
import 'vouchers_page.dart';
import 'warehouses_page.dart';
import 'widgets.dart';

const _dest = <(IconData, String)>[
  (Icons.space_dashboard_outlined, 'الرئيسية'),
  (Icons.south_west_rounded, 'الوارد'),
  (Icons.north_east_rounded, 'الصادر'),
  (Icons.inventory_2_outlined, 'المخزون'),
  (Icons.bar_chart_rounded, 'التقارير'),
  (Icons.groups_outlined, 'الجهات'),
  (Icons.warehouse_outlined, 'المخازن'),
  (Icons.settings_outlined, 'الإعدادات'),
];

Widget pageAt(int i, ValueChanged<int> nav) => switch (i) {
      0 => HomePage(onNav: nav),
      1 => const VouchersPage(type: VType.inbound, key: ValueKey('in')),
      2 => const VouchersPage(type: VType.outbound, key: ValueKey('out')),
      3 => const StockPage(),
      4 => const ReportsPage(),
      5 => const PartiesPage(),
      6 => const WarehousesPage(),
      _ => const SettingsPage(),
    };

/// Side rail on desktop/tablet, bottom bar (4 tabs + "more") on phones.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  bool more = false;

  void nav(int x) => setState(() => (i = x, more = false));

  late final AppLifecycleListener _life;
  Timer? _timer;
  bool _busy = false, _exiting = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onExitRequested: _onExit);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _life.dispose();
    super.dispose();
  }

  /// Daily backup, and the stock sheet once its time has come.
  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await BackupService.autoBackup();
      if (await DailyService.sheetDue()) {
        await DailyService.writeSheet();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('ورقة الجرد بتاعة النهارده جاهزة'),
            duration: const Duration(minutes: 5),
            action: SnackBarAction(
              label: 'طباعة',
              onPressed: () async => PdfService.printBytes(await DailyService.sheetBytes(), 'ورقة الجرد'),
            ),
          ));
        }
      }
    } catch (_) {
      // retried on the next tick
    } finally {
      _busy = false;
    }
  }

  Future<AppExitResponse> _onExit() async {
    if (_exiting) return AppExitResponse.cancel;
    _exiting = true;
    try {
      final choice = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('قفل البرنامج'),
          content: Text('${VoucherFormCubit.unsavedForms > 0 ? 'فيه سند مفتوح لسه ما اتحفظش وهيضيع لو قفلت.\n\n' : ''}تعمل نسخة احتياطية قبل ما تقفل؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
            OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('لأ، اقفل')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('أيوه، اعمل نسخة')),
          ],
        ),
      );
      if (choice == null) return AppExitResponse.cancel;
      if (choice) {
        try {
          await BackupService.create('close');
        } catch (e) {
          if (!mounted) return AppExitResponse.exit;
          if (!await confirm(context, 'النسخة فشلت', 'معرفتش أعمل النسخة:\n$e\n\nتقفل برضو؟', ok: 'اقفل', danger: true)) return AppExitResponse.cancel;
        }
      }
      try {
        await DailyService.writeSheet();
      } catch (_) {}
      return AppExitResponse.exit;
    } finally {
      _exiting = false;
    }
  }

  Widget _banner() {
    if (Repo.i.writable) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF3CD),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivationPage(onDone: () {
              Repo.i.writable = LicenseService.activated;
              Repo.i.notify();
              if (mounted) setState(() {});
              Navigator.of(context).maybePop();
            }))),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(Icons.lock_outline, size: 20, color: Color(0xFF8A6D00)),
            SizedBox(width: 8),
            Expanded(child: Text('وضع القراءة فقط — اضغط هنا للتفعيل', style: TextStyle(color: Color(0xFF8A6D00), fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_left, color: Color(0xFF8A6D00)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) {
      final extended = MediaQuery.sizeOf(context).width >= 1250;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: extended,
            selectedIndex: i,
            onDestinationSelected: nav,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.warehouse_rounded, color: Colors.white),
                ),
                if (extended) ...[
                  const SizedBox(width: 10),
                  const Text('المستودع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
            destinations: [for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Column(children: [_banner(), _WarehouseBar(onManage: () => nav(6)), Expanded(child: pageAt(i, nav))])),
        ]),
      );
    }
    final tab = more || i > 3 ? 4 : i;
    return Scaffold(
      body: Column(children: [_banner(), _WarehouseBar(onManage: () => nav(6)), Expanded(child: more ? _More(onOpen: nav) : pageAt(i, nav))]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (x) => x == 4 ? setState(() => more = true) : nav(x),
        destinations: [
          for (final d in _dest.take(4)) NavigationDestination(icon: Icon(d.$1), label: d.$2),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.onOpen});
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'المزيد',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListCard(children: [
            for (var x = 4; x < _dest.length; x++)
              ListTile(leading: Icon(_dest[x].$1), title: Text(_dest[x].$2), trailing: const Icon(Icons.chevron_left), onTap: () => onOpen(x)),
          ]),
        ]),
      );
}

/// A strip under the top bar showing the current warehouse, with a quick switch.
class _WarehouseBar extends StatefulWidget {
  const _WarehouseBar({required this.onManage});
  final VoidCallback onManage;
  @override
  State<_WarehouseBar> createState() => _WarehouseBarState();
}

class _WarehouseBarState extends State<_WarehouseBar> {
  late final StreamSubscription<void> _sub;
  List<Warehouse> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Repo.i.changes.listen((_) => _load());
  }

  Future<void> _load() async {
    final all = await Repo.i.warehouses();
    if (mounted) setState(() => _all = all);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_all.isEmpty) return const SizedBox.shrink();
    final current = _all.firstWhere((w) => w.id == Repo.i.currentWarehouseId, orElse: () => _all.first);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const Icon(Icons.warehouse_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('المخزن:', style: TextStyle(color: Colors.black54)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: current.id,
                  items: [for (final w in _all) DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (id) {
                    if (id != null) Repo.i.setCurrentWarehouse(id);
                  },
                ),
              ),
            ),
            IconButton(tooltip: 'إدارة المخازن', icon: const Icon(Icons.settings_outlined, size: 20), onPressed: widget.onManage),
          ]),
        ),
        const Divider(height: 1),
      ]),
    );
  }
}
