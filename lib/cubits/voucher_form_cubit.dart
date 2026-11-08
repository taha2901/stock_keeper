import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/repo.dart';

class FLine {
  final int uid;
  final Item item;
  final double qty;
  final String note;
  final double? price;

  /// Balance available before this voucher (used to block over-issuing).
  final double available;
  const FLine(this.uid, this.item, this.qty, this.note, this.available, [this.price]);
  FLine copy({double? qty, String? note, Object? price = _keep}) =>
      FLine(uid, item, qty ?? this.qty, note ?? this.note, available, identical(price, _keep) ? this.price : price as double?);
  double get total => qty * (price ?? 0);
}

const _keep = Object();

class VForm {
  final int? id;
  final VType type;
  final int number;
  final DateTime date;
  final int warehouseId;
  final String warehouseName;
  final Party? party, recipient;
  final String refNo, licenseNo, notes;
  final String? attachment;
  final List<FLine> lines;
  final bool loading, saving;
  final String? error, duplicate, dateWarning;
  final int? savedId;

  const VForm({
    this.id,
    required this.type,
    this.number = 0,
    required this.date,
    this.warehouseId = 0,
    this.warehouseName = '',
    this.party,
    this.recipient,
    this.refNo = '',
    this.licenseNo = '',
    this.notes = '',
    this.attachment,
    this.lines = const [],
    this.loading = false,
    this.saving = false,
    this.error,
    this.duplicate,
    this.dateWarning,
    this.savedId,
  });

  VForm copy({
    int? id,
    int? number,
    DateTime? date,
    int? warehouseId,
    String? warehouseName,
    Object? party = _keep,
    Object? recipient = _keep,
    String? refNo,
    String? licenseNo,
    String? notes,
    Object? attachment = _keep,
    List<FLine>? lines,
    bool? loading,
    bool? saving,
    String? error,
    String? duplicate,
    String? dateWarning,
    int? savedId,
  }) =>
      VForm(
        id: id ?? this.id,
        type: type,
        number: number ?? this.number,
        date: date ?? this.date,
        warehouseId: warehouseId ?? this.warehouseId,
        warehouseName: warehouseName ?? this.warehouseName,
        party: identical(party, _keep) ? this.party : party as Party?,
        recipient: identical(recipient, _keep) ? this.recipient : recipient as Party?,
        refNo: refNo ?? this.refNo,
        licenseNo: licenseNo ?? this.licenseNo,
        notes: notes ?? this.notes,
        attachment: identical(attachment, _keep) ? this.attachment : attachment as String?,
        lines: lines ?? this.lines,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        error: error,
        duplicate: duplicate,
        dateWarning: dateWarning,
        savedId: savedId,
      );
}

class VoucherFormCubit extends Cubit<VForm> {
  VoucherFormCubit(VType type, int? id)
      : super(VForm(type: type, date: today(), warehouseId: Repo.i.currentWarehouseId, loading: id != null)) {
    if (id != null) {
      _load(id);
    } else {
      _initWarehouse();
    }
  }

  Future<void> _initWarehouse() async {
    final w = await Repo.i.warehouse(Repo.i.currentWarehouseId);
    if (w != null && !isClosed) emit(state.copy(warehouseName: w.name));
  }

  int _uid = 0;
  bool _saving = false;
  DateTime? _loadedDate;

  /// True once the user has changed anything since the form opened.
  bool dirty = false;

  /// Number of open forms with unsaved changes, so closing the app can warn about them.
  static int unsavedForms = 0;

  void _touch() {
    if (!dirty) {
      dirty = true;
      unsavedForms++;
    }
  }

  void _clean() {
    if (dirty) {
      dirty = false;
      unsavedForms--;
    }
  }

  @override
  Future<void> close() {
    _clean();
    return super.close();
  }

  Future<void> _load(int id) async {
    final v = await Repo.i.voucher(id);
    _loadedDate = v.date;
    final lines = <FLine>[];
    for (final l in v.lines) {
      lines.add(FLine(++_uid, l.item, l.qty, l.note, await Repo.i.balance(l.item.id!, warehouseId: v.warehouseId, excludeVoucher: id), l.price));
    }
    emit(VForm(
      id: v.id,
      type: v.type,
      number: v.number,
      date: v.date,
      warehouseId: v.warehouseId,
      warehouseName: v.warehouseName,
      party: v.partyId == null ? null : Party(id: v.partyId, type: v.type.partyType, name: v.partyName),
      recipient: v.recipientId == null ? null : Party(id: v.recipientId, type: PartyType.recipient, name: v.recipientName),
      refNo: v.refNo,
      licenseNo: v.licenseNo,
      notes: v.notes,
      attachment: v.attachment,
      lines: lines,
    ));
  }

  void setDate(DateTime d) {
    _touch();
    emit(state.copy(date: d));
  }

  void setParty(Party? p) {
    _touch();
    emit(state.copy(party: p));
  }

  void setRecipient(Party? p) {
    _touch();
    emit(state.copy(recipient: p));
  }

  void setRef(String v) {
    _touch();
    emit(state.copy(refNo: v));
  }

  void setLicense(String v) {
    _touch();
    emit(state.copy(licenseNo: v));
  }

  Future<void> setWarehouse(Warehouse w) async {
    _touch();
    emit(state.copy(warehouseId: w.id, warehouseName: w.name));
    // recompute each line's available balance in the newly chosen warehouse
    final lines = <FLine>[];
    for (final l in state.lines) {
      lines.add(FLine(l.uid, l.item, l.qty, l.note, await Repo.i.balance(l.item.id!, warehouseId: w.id!, excludeVoucher: state.id), l.price));
    }
    emit(state.copy(lines: lines));
  }

  void setNotes(String v) {
    _touch();
    emit(state.copy(notes: v));
  }

  void setAttachment(String? path) {
    _touch();
    emit(state.copy(attachment: path));
  }


  /// Adds an item line. If the item is already in the voucher, its quantity is increased.
  Future<void> addItem(Item it, {double qty = 0, String note = '', double? price}) async {
    _touch();
    final i = state.lines.indexWhere((l) => l.item.id == it.id);
    if (i >= 0) {
      final l = state.lines[i];
      _replace(l.uid, l.copy(qty: l.qty + qty, price: price ?? l.price));
      return;
    }
    final av = await Repo.i.balance(it.id!, warehouseId: state.warehouseId, excludeVoucher: state.id);
    emit(state.copy(lines: [...state.lines, FLine(++_uid, it, qty, note, av, price ?? it.price)]));
  }

  void setQty(int uid, double q) => _replace(uid, _line(uid).copy(qty: q));
  void setPrice(int uid, double? p) => _replace(uid, _line(uid).copy(price: p));
  void setLineNote(int uid, String n) => _replace(uid, _line(uid).copy(note: n));
  void remove(int uid) {
    _touch();
    emit(state.copy(lines: state.lines.where((l) => l.uid != uid).toList()));
  }


  FLine _line(int uid) => state.lines.firstWhere((l) => l.uid == uid);
  void _replace(int uid, FLine n) {
    _touch();
    emit(state.copy(lines: [for (final l in state.lines) l.uid == uid ? n : l]));
  }


  /// Adds Excel rows to the voucher. Returns the rows whose item wasn't found.
  Future<List<ImportRow>> importRows(List<ImportRow> rows) async {
    final items = await Repo.i.allItems();
    final missing = <ImportRow>[];
    for (final r in rows) {
      final t = r.name.trim().toLowerCase();
      // a supplier code written as "[CODE] description"; loose substrings could pick the wrong item
      final bracket = RegExp(r'\[(.+?)\]').firstMatch(t)?.group(1)?.trim();
      final match = items.where((it) {
        final code = it.code.toLowerCase().replaceAll('[', '').replaceAll(']', '').trim();
        return it.name.toLowerCase() == t ||
            (it.nameEn.isNotEmpty && it.nameEn.toLowerCase() == t) ||
            (code.isNotEmpty && (code == t || code == bracket));
      }).firstOrNull;
      if (match == null) {
        missing.add(r);
      } else {
        await addItem(match, qty: r.qty, note: r.note, price: r.price);
      }
    }
    return missing;
  }

  /// [force] saves even though the invoice number already exists (the user confirmed).
  Future<void> save({bool force = false, bool dateOk = false}) async {
    if (_saving) return; // a double click must not create two vouchers
    _saving = true;
    try {
      await _save(force, dateOk);
    } finally {
      _saving = false;
    }
  }

  Future<void> _save(bool force, bool dateOk) async {
    final s = state;
    String? err;
    if (s.warehouseId == 0) {
      err = 'اختار المخزن';
    } else if (s.party == null) {
      err = 'اختار ${s.type.partyType.label}';
    } else if (s.lines.isEmpty) {
      err = 'ضيف صنف واحد على الأقل';
    } else {
      for (final l in s.lines) {
        if (l.qty <= 0) {
          err = 'اكتب كمية للصنف: ${l.item.name}';
          break;
        }
        if (l.price != null && l.price! < 0) {
          err = 'السعر مينفعش يبقى بالسالب: ${l.item.name}';
          break;
        }
        if (!s.type.isIn && l.qty > l.available + 1e-6) {
          err = 'الكمية أكبر من الرصيد: ${l.item.name}\nالمتاح ${fmtQty(l.available)} ${l.item.unit}';
          break;
        }
      }
    }
    if (err != null) return emit(s.copy(error: err));

    // only asked when the date is new or was changed, not on every edit of an old voucher
    if (!dateOk && s.date != _loadedDate) {
      final now = today();
      final warn = s.date.isAfter(now)
          ? 'التاريخ ${fmtDate(s.date)} لسه مجاش (النهارده ${fmtDate(now)}).'
          : now.difference(s.date).inDays > 365
              ? 'التاريخ ${fmtDate(s.date)} قديم أكتر من سنة.'
              : null;
      if (warn != null) return emit(s.copy(dateWarning: '$warn\nالتاريخ بيحدد ترتيب الأسعار، فاتأكد إنه صح.\n\nتحفظ برضو؟'));
    }

    if (s.type.isIn && s.id != null) {
      final qty = <int, double>{};
      for (final l in s.lines) {
        qty[l.item.id!] = (qty[l.item.id!] ?? 0) + l.qty;
      }
      final bad = await Repo.i.receiptConflicts(await Repo.i.voucher(s.id!), qty);
      if (bad.isNotEmpty) {
        return emit(s.copy(error: 'مينفعش تقلل الكمية: اتصرف منها بالفعل والرصيد هيبقى بالسالب:\n${bad.join('، ')}'));
      }
    }

    if (s.type.isIn && !force && s.refNo.trim().isNotEmpty) {
      final same = await Repo.i.receiptsWithRef(s.refNo, s.warehouseId, excludeId: s.id);
      if (same.isNotEmpty) {
        final o = same.first;
        return emit(s.copy(
            duplicate: 'رقم الفاتورة «${s.refNo.trim()}» متسجل قبل كده:\n${o.title} بتاريخ ${fmtDate(o.date)} - ${o.partyName}\n\nتحفظها برضو؟'));
      }
    }

    emit(s.copy(saving: true));
    try {
      final id = await Repo.i.saveVoucher(Voucher(
        id: s.id,
        type: s.type,
        date: s.date,
        warehouseId: s.warehouseId,
        partyId: s.party!.id,
        recipientId: s.recipient?.id,
        refNo: s.refNo,
        licenseNo: s.licenseNo,
        notes: s.notes,
        attachment: s.attachment,
        lines: [for (final l in s.lines) VoucherLine(l.item, l.qty, l.note, l.price)],
      ));
      _clean();
      emit(state.copy(saving: false, savedId: id));
    } catch (e) {
      emit(state.copy(saving: false, error: 'حصل خطأ في الحفظ: $e'));
    }
  }
}
