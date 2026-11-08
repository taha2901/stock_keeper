import 'dart:async';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/repo.dart';

class Load<T> {
  final T? data;
  final String? error;
  const Load({this.data, this.error});
  bool get loading => data == null && error == null;
}

/// Base cubit: loads data once, then reloads automatically after any database change.
abstract class LoadCubit<T> extends Cubit<Load<T>> {
  LoadCubit() : super(const Load()) {
    _sub = Repo.i.changes.listen((_) => reload());
    reload();
  }
  late final StreamSubscription<void> _sub;

  Future<T> fetch();

  Future<void> reload() async {
    try {
      final d = await fetch();
      if (!isClosed) emit(Load(data: d));
    } catch (e) {
      if (!isClosed) emit(Load(data: state.data, error: '$e'));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}

class HomeCubit extends LoadCubit<HomeStats> {
  @override
  Future<HomeStats> fetch() => Repo.i.homeStats();
}

class StockCubit extends LoadCubit<List<ItemStock>> {
  String q = '';
  bool lowOnly = false;
  bool allItems = false;

  void search(String v) => (q = v, reload());
  void toggleLow() => (lowOnly = !lowOnly, reload());
  void toggleAll() => (allItems = !allItems, reload());

  @override
  Future<List<ItemStock>> fetch() async {
    final all = await Repo.i.stock(q: q, includeEmpty: allItems);
    return lowOnly ? all.where((s) => s.low).toList() : all;
  }
}

class PartiesCubit extends LoadCubit<List<Party>> {
  PartiesCubit(this.type);
  final PartyType type;
  String q = '';

  void search(String v) => (q = v, reload());

  @override
  Future<List<Party>> fetch() => Repo.i.parties([type], q: q);
}

class VouchersCubit extends LoadCubit<List<Voucher>> {
  VouchersCubit(this.type);
  final VType type;
  String q = '';
  DateTimeRange? range;

  void search(String v) => (q = v, reload());
  void setRange(DateTimeRange? r) => (range = r, reload());

  @override
  Future<List<Voucher>> fetch() => Repo.i.vouchers(type, q: q, from: range?.start, to: range?.end, warehouseId: Repo.i.currentWarehouseId);
}

class LedgerCubit extends LoadCubit<List<LedgerRow>> {
  LedgerCubit(this.itemId, this.warehouseId);
  final int itemId, warehouseId;

  @override
  Future<List<LedgerRow>> fetch() async => (await Repo.i.ledger(itemId, warehouseId: warehouseId)).reversed.toList();
}

class ReportData {
  const ReportData({this.moves = const [], this.balances = const []});
  final List<MovementRow> moves;
  final List<BalanceRow> balances;
}

enum ReportMode {
  inbound('وارد', 'تقرير الوارد'),
  outbound('صادر', 'تقرير الصادر'),
  balance('الرصيد', 'تقرير الرصيد');

  const ReportMode(this.label, this.title);
  final String label, title;
}

/// Sums movements per item (the inbound / outbound reports are always by item).
/// Each row keeps its movements, oldest first, for the expandable detail.
List<GroupRow> groupMoves(List<MovementRow> rows) {
  final byItem = <int, List<MovementRow>>{};
  for (final r in rows) {
    byItem.putIfAbsent(r.itemId, () => []).add(r);
  }
  return [
    for (final l in byItem.values)
      GroupRow(
        l.first.item,
        l.fold(0.0, (a, r) => a + r.qty),
        l.map((r) => r.voucherId).toSet().length,
        l.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b),
        l.fold(0.0, (a, r) => a + r.cost.value),
        l.any((r) => r.cost.missing),
        [...l]..sort((a, b) => a.date.compareTo(b.date)),
      ),
  ]..sort((a, b) => a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase()));
}

class ReportsCubit extends LoadCubit<ReportData> {
  DateTimeRange? range = DateTimeRange(start: DateTime(today().year, today().month), end: today());
  ReportMode mode = ReportMode.inbound;
  Party? party, recipient;
  String q = '', ref = '';

  /// Supplier/site, recipient and invoice filters only apply to a single direction.
  bool get singleType => mode == ReportMode.inbound || mode == ReportMode.outbound;

  void setRange(DateTimeRange? r) => (range = r, reload());
  void setMode(ReportMode m) => (mode = m, party = null, recipient = null, ref = '', reload());
  void setParty(Party? p) => (party = p, reload());
  void setRecipient(Party? p) => (recipient = p, reload());
  void setRef(String v) => (ref = v, reload());
  void search(String v) => (q = v, reload());

  @override
  Future<ReportData> fetch() async {
    if (mode == ReportMode.balance) {
      return ReportData(balances: await Repo.i.balanceReport(from: range?.start, to: range?.end, q: q, warehouseId: Repo.i.currentWarehouseId));
    }
    final type = mode == ReportMode.inbound ? VType.inbound : VType.outbound;
    return ReportData(
      moves: await Repo.i.movements(from: range?.start, to: range?.end, type: type, partyId: party?.id, recipientId: recipient?.id, ref: ref, q: q, warehouseId: Repo.i.currentWarehouseId),
    );
  }
}
