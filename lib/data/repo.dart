import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../core/db.dart';
import '../core/format.dart';
import 'arabic_names.dart';
import 'models.dart';

/// Per-line FIFO result. Costs and remaining stock are both computed per
/// (warehouse, item), so each warehouse keeps its own balances and prices.
class FifoResult {
  /// Value of every voucher line, by line id.
  final Map<int, LineCost> costs;

  /// What is still in stock, keyed by (warehouseId, itemId).
  final Map<(int, int), LineCost> remaining;
  const FifoResult(this.costs, this.remaining);
}

/// All database access. Every write calls [notify] so open screens refresh.
class Repo {
  Repo._();
  static final i = Repo._();

  Database get _db => AppDb.db;

  /// The warehouse the UI is currently showing / defaulting to. Set at startup.
  int currentWarehouseId = 0;

  /// When false the app is read-only (before activation): view, export and print
  /// still work, but nothing can be saved or deleted. Set by LicenseService.load().
  bool writable = true;
  void _guard() {
    if (!writable) throw 'البرنامج في وضع القراءة فقط. لازم التفعيل عشان تسجل أو تعدل.';
  }

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void notify() => _changes.add(null);

  // ---------------- warehouses ----------------
  Future<List<Warehouse>> warehouses() async =>
      (await _db.query('warehouses', orderBy: 'id')).map(Warehouse.fromMap).toList();

  Future<Warehouse?> warehouse(int id) async {
    final r = await _db.query('warehouses', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : Warehouse.fromMap(r.first);
  }

  Future<Warehouse> saveWarehouse(Warehouse w) async {
    _guard();
    try {
      final id = w.id ?? await _db.insert('warehouses', {...w.toMap(), 'created_at': DateTime.now().toIso8601String()});
      if (w.id != null) await _db.update('warehouses', w.toMap(), where: 'id=?', whereArgs: [w.id]);
      notify();
      return Warehouse(id: id, name: w.name.trim());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw 'المخزن «${w.name.trim()}» موجود قبل كده';
      rethrow;
    }
  }

  Future<void> deleteWarehouse(int id) async {
    _guard();
    final n = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM warehouses'));
    if ((n ?? 0) <= 1) throw 'لازم يفضل مخزن واحد على الأقل.';
    final used = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM vouchers WHERE warehouse_id=?', [id]));
    if ((used ?? 0) > 0) throw 'مينفعش تمسح مخزن عليه حركات.';
    await _db.delete('warehouses', where: 'id=?', whereArgs: [id]);
    if (currentWarehouseId == id) currentWarehouseId = (await warehouses()).first.id!;
    notify();
  }

  /// Loads the saved current warehouse, falling back to the first one.
  Future<void> loadCurrentWarehouse() async {
    final all = await warehouses();
    final saved = int.tryParse(await setting('current_wh'));
    currentWarehouseId = all.any((w) => w.id == saved) ? saved! : all.first.id!;
  }

  Future<void> setCurrentWarehouse(int id) async {
    currentWarehouseId = id;
    await setSetting('current_wh', '$id');
    notify();
  }

  // ---------------- FIFO ----------------
  /// Order of movements on the same day: outside receipts, then transfers (each
  /// transfer's issue before its receipt), then issues. Shared by FIFO and the ledger.
  static const _rank = "CASE WHEN v.transfer_id IS NOT NULL THEN 1 WHEN v.type = 'in' THEN 0 ELSE 2 END";

  /// FIFO over the whole history (or up to [until]), computed on demand and never
  /// stored, so filling in a missing price or editing a voucher corrects every issue
  /// that depends on it. Each (warehouse, item) is an independent queue.
  ///
  /// - An issue that finds no stock (dated before the receipt that covers it) is
  ///   unpriced until a later receipt arrives; that receipt covers it first, so the
  ///   quantity left in the queue always equals the real balance.
  /// - A transfer's receipt carries exactly the price layers its issue took at the
  ///   source, so value moves with the goods and follows later price corrections.
  Future<FifoResult> fifo({DateTime? until}) async {
    final rows = await _db.rawQuery('''
      SELECT l.id, l.item_id, l.qty, l.price, v.type, v.id AS vid, v.warehouse_id AS wid, v.transfer_id AS tid
      FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id
      ${until == null ? '' : 'WHERE v.date <= ?'}
      ORDER BY v.date, $_rank, v.id, l.id''', [if (until != null) dbDate(until)]);

    // pair each transfer receipt line with its issue line (same transfer, item, n-th occurrence)
    final seen = <(int, int), int>{};
    final outOf = <(int, int, int), int>{};
    final nth = <int, int>{};
    for (final m in rows) {
      if (m['tid'] == null) continue;
      final k = (m['vid'] as int, m['item_id'] as int);
      final n = seen[k] = (seen[k] ?? 0) + 1;
      nth[m['id'] as int] = n;
      if (m['type'] == 'out') outOf[(m['tid'] as int, m['item_id'] as int, n)] = m['id'] as int;
    }
    final pair = <int, int>{}; // receipt line -> issue line
    for (final m in rows) {
      if (m['tid'] == null || m['type'] != 'in') continue;
      final o = outOf[(m['tid'] as int, m['item_id'] as int, nth[m['id'] as int]!)];
      if (o != null) pair[m['id'] as int] = o;
    }

    // A transfer receipt needs its issue's final cost, which can still change later in
    // the walk (a shortage at the source filled by a later receipt). Re-run with the
    // final costs until nothing changes; without such cases one pass is enough.
    var given = <int, List<CostSlice>>{};
    late FifoResult res;
    for (var pass = 0; pass < 10; pass++) {
      res = _walk(rows, pair, given);
      final next = <int, List<CostSlice>>{};
      var changed = false;
      pair.forEach((inId, outId) {
        final want = res.costs[outId]?.slices ?? const [];
        next[inId] = want;
        if (!_same(res.costs[inId]?.slices ?? const [], want)) changed = true;
      });
      if (!changed) break;
      given = next;
    }
    return res;
  }

  FifoResult _walk(List<Map<String, Object?>> rows, Map<int, int> pair, Map<int, List<CostSlice>> given) {
    final queues = <(int, int), List<CostSlice>>{};
    final shortages = <(int, int), List<(int, double)>>{}; // issue line, qty still uncovered
    final taken = <int, List<CostSlice>>{}, filled = <int, List<CostSlice>>{};
    final short = <int, double>{};
    final inCost = <int, List<CostSlice>>{};
    List<CostSlice> outCost(int id) => _mergeSamePrice([
          ...?taken[id],
          ...?filled[id],
          if ((short[id] ?? 0) > 1e-9) CostSlice(short[id]!, null),
        ]);

    for (final m in rows) {
      final id = m['id'] as int;
      final key = (m['wid'] as int, m['item_id'] as int);
      final queue = queues.putIfAbsent(key, () => []);
      final qty = (m['qty'] as num).toDouble();
      if (m['type'] == 'in') {
        final from = pair[id];
        var slices = from == null ? [CostSlice(qty, (m['price'] as num?)?.toDouble())] : (given[id] ?? outCost(from));
        if ((slices.fold(0.0, (a, s) => a + s.qty) - qty).abs() > 1e-6) slices = [CostSlice(qty, null)];
        inCost[id] = slices;
        for (final s in slices) {
          var rem = s.qty;
          final owed = shortages[key];
          while (rem > 1e-9 && owed != null && owed.isNotEmpty) {
            final (line, need) = owed.first;
            final q = need <= rem ? need : rem;
            filled.putIfAbsent(line, () => []).add(CostSlice(q, s.price));
            short[line] = short[line]! - q;
            rem -= q;
            if (need - q <= 1e-9) {
              owed.removeAt(0);
            } else {
              owed[0] = (line, need - q);
            }
          }
          if (rem > 1e-9) queue.add(CostSlice(rem, s.price));
        }
        continue;
      }
      var left = qty;
      final t = taken[id] = <CostSlice>[];
      while (left > 1e-9 && queue.isNotEmpty) {
        final head = queue.first;
        final q = head.qty <= left ? head.qty : left;
        t.add(CostSlice(q, head.price));
        left -= q;
        if (head.qty - q <= 1e-9) {
          queue.removeAt(0);
        } else {
          queue[0] = CostSlice(head.qty - q, head.price);
        }
      }
      if (left > 1e-9) {
        // issued before any receipt covers it: unpriced until a later receipt arrives
        short[id] = left;
        shortages.putIfAbsent(key, () => []).add((id, left));
      }
    }
    return FifoResult(
      {
        for (final e in inCost.entries) e.key: LineCost(_mergeSamePrice(e.value)),
        for (final id in taken.keys) id: LineCost(outCost(id)),
      },
      {for (final e in queues.entries) e.key: LineCost(e.value)},
    );
  }

  static bool _same(List<CostSlice> a, List<CostSlice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i].qty - b[i].qty).abs() > 1e-9 || a[i].price != b[i].price) return false;
    }
    return true;
  }

  List<CostSlice> _mergeSamePrice(List<CostSlice> s) {
    final out = <CostSlice>[];
    for (final x in s) {
      if (out.isNotEmpty && out.last.price == x.price) {
        out[out.length - 1] = CostSlice(out.last.qty + x.qty, x.price);
      } else {
        out.add(x);
      }
    }
    return out;
  }

  // ---------------- item names ----------------
  /// Sort by the name the keeper sees.
  static String get _order => Item.mode == NameMode.en ? 'i.name COLLATE NOCASE' : "COALESCE(NULLIF(i.name_ar, ''), i.name) COLLATE NOCASE";

  /// Item search over every name and the code. Takes 4 arguments.
  static const _itemLike = '(i.name LIKE ? OR i.name_ar LIKE ? OR i.name_en LIKE ? OR i.code LIKE ?)';
  static List<String> _likeArgs(String q) => List.filled(4, '%${q.trim()}%');

  Future<void> loadNameMode() async => Item.mode = NameMode.of(await setting('name_mode', NameMode.both.key));

  Future<void> setNameMode(NameMode m) async {
    Item.mode = m;
    await setSetting('name_mode', m.key);
    notify();
  }

  /// Saves Arabic names (item id -> name; '' clears it). Refuses names that would
  /// make two items look the same.
  Future<void> saveArabicNames(Map<int, String> names) async {
    _guard();
    String shown(Item it) {
      final ar = (names[it.id] ?? it.nameAr).trim();
      return ar.isNotEmpty ? ar : it.name.trim();
    }

    final byShown = <String, List<Item>>{};
    for (final it in await allItems()) {
      byShown.putIfAbsent(shown(it).toLowerCase(), () => []).add(it);
    }
    final dup = byShown.values.where((l) => l.length > 1).firstOrNull;
    if (dup != null) {
      throw 'الاسم «${shown(dup.first)}» متكرر لـ ${dup.length} أصناف:\n${dup.map((i) => '• ${i.name}').join('\n')}\nغيّر واحد منهم عشان محدش يتلخبط.';
    }
    final b = _db.batch();
    names.forEach((id, n) => b.update('items', {'name_ar': n.trim()}, where: 'id = ?', whereArgs: [id]));
    await b.commit(noResult: true);
    notify();
  }

  /// At startup: when the naming rules learned new items since the last run, gives
  /// them their Arabic names once. Names already set (or typed) are never touched.
  Future<void> refreshArabicNames() async {
    if ((int.tryParse(await setting('names_version')) ?? 1) >= ArabicNames.version) return;
    if (await AppDb.fillArabicNames(_db) > 0) notify();
    await setSetting('names_version', '${ArabicNames.version}');
  }

  /// Fills the Arabic name of every item that has none. Returns how many were filled.
  Future<int> fillArabicNames() async {
    _guard();
    final n = await AppDb.fillArabicNames(_db);
    if (n > 0) notify();
    return n;
  }

  Future<Set<String>> _shownArabic({int? except}) async => {
        for (final it in await allItems())
          if (it.id != except)
            if (it.hasAr) it.nameAr.trim() else if (ArabicNames.isArabic(it.name)) it.name.trim(),
      };

  // ---------------- items & stock ----------------
  Future<List<ItemStock>> stock({String q = '', int? warehouseId, bool includeEmpty = false}) async {
    final wh = warehouseId ?? currentWarehouseId;
    final f = await fifo();
    final rows = await _db.rawQuery('''
      SELECT i.*,
        COALESCE(SUM(CASE WHEN v.type='in'  THEN l.qty END), 0) AS in_qty,
        COALESCE(SUM(CASE WHEN v.type='out' THEN l.qty END), 0) AS out_qty
      FROM items i
      LEFT JOIN voucher_lines l ON l.item_id = i.id
      LEFT JOIN vouchers v ON v.id = l.voucher_id AND v.warehouse_id = ?
      WHERE $_itemLike
      GROUP BY i.id
      ${includeEmpty ? '' : 'HAVING COUNT(v.id) > 0'}
      ORDER BY $_order''', [wh, ..._likeArgs(q)]);
    return rows.map((m) {
      final left = f.remaining[(wh, m['id'] as int)] ?? LineCost.none;
      return ItemStock(Item.fromMap(m), (m['in_qty'] as num).toDouble(), (m['out_qty'] as num).toDouble(), left.value, left.missing);
    }).toList();
  }

  Future<List<Item>> allItems() async =>
      (await _db.rawQuery('SELECT i.* FROM items i ORDER BY $_order')).map(Item.fromMap).toList();

  /// Balance of one item in one warehouse (optionally ignoring one voucher).
  Future<double> balance(int itemId, {int? warehouseId, int? excludeVoucher}) async {
    final wh = warehouseId ?? currentWarehouseId;
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN v.type='in' THEN l.qty ELSE -l.qty END), 0) AS b
      FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id
      WHERE l.item_id = ? AND v.warehouse_id = ? AND v.id <> ?''', [itemId, wh, excludeVoucher ?? -1]);
    return (r.first['b'] as num).toDouble();
  }

  Future<Item> saveItem(Item it) async {
    _guard();
    // a new item with an English name gets its Arabic name right away
    if (it.id == null && !it.hasAr && !ArabicNames.isArabic(it.name)) {
      it = it.copyWith(nameAr: ArabicNames.uniqueOne(it.name, it.code, await _shownArabic()));
    }
    final shown = it.hasAr ? it.nameAr.trim() : it.name.trim();
    if ((await _shownArabic(except: it.id)).any((n) => n.toLowerCase() == shown.toLowerCase())) {
      throw 'الاسم «$shown» مستخدم لصنف تاني. غيّره عشان محدش يتلخبط.';
    }
    try {
      final id = it.id ?? await _db.insert('items', it.toMap());
      if (it.id != null) await _db.update('items', it.toMap(), where: 'id=?', whereArgs: [it.id]);
      notify();
      return Item(id: id, name: it.name.trim(), nameAr: it.nameAr.trim(), nameEn: it.nameEn.trim(), code: it.code.trim(), unit: it.unit, minQty: it.minQty, price: it.price);
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw 'الصنف «${it.name.trim()}» موجود قبل كده';
      rethrow;
    }
  }

  Future<void> deleteItem(int id) async {
    _guard();
    final used = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM voucher_lines WHERE item_id=?', [id]));
    if ((used ?? 0) > 0) throw 'مينفعش تمسح صنف عليه حركات. امسح الحركات الأول.';
    await _db.delete('items', where: 'id=?', whereArgs: [id]);
    notify();
  }

  /// Item card: every movement of one item in one warehouse, with running balance.
  Future<List<LedgerRow>> ledger(int itemId, {int? warehouseId}) async {
    final wh = warehouseId ?? currentWarehouseId;
    final rows = await _db.rawQuery('''
      SELECT v.id, v.type, v.number, v.date, v.ref_no, v.notes, v.transfer_id, p.name AS party_name, SUM(l.qty) AS qty,
        GROUP_CONCAT(l.id) AS line_ids
      FROM voucher_lines l
      JOIN vouchers v ON v.id = l.voucher_id
      LEFT JOIN parties p ON p.id = v.party_id
      WHERE l.item_id = ? AND v.warehouse_id = ?
      GROUP BY v.id ORDER BY v.date, $_rank, v.id''', [itemId, wh]);
    final f = await fifo();
    var bal = 0.0, val = 0.0;
    return rows.map((m) {
      final t = VType.of(m['type'] as String);
      final q = (m['qty'] as num).toDouble();
      bal += t.isIn ? q : -q;
      final cost = (m['line_ids'] as String).split(',').map((s) => f.costs[int.parse(s)] ?? LineCost.none).fold(LineCost.none, (a, c) => a + c);
      val += t.isIn ? cost.value : -cost.value;
      return LedgerRow(m['id'] as int, m['number'] as int, t, DateTime.parse(m['date'] as String),
          m['transfer_id'] != null ? _transferLabel(m['notes'] as String) : (m['party_name'] as String?) ?? '', m['ref_no'] as String, q, bal, cost, val);
    }).toList();
  }

  /// "تحويل إلى: مخزن جدة" out of a transfer voucher's notes (without the free text after it).
  static String _transferLabel(String notes) => notes.split(' - ').first;

  // ---------------- parties ----------------
  Future<List<Party>> parties(List<PartyType> types, {String q = ''}) async {
    final rows = await _db.query('parties',
        where: 'type IN (${List.filled(types.length, '?').join(',')}) AND name LIKE ?',
        whereArgs: [...types.map((t) => t.key), '%${q.trim()}%'],
        orderBy: 'name COLLATE NOCASE');
    return rows.map(Party.fromMap).toList();
  }

  Future<Party> saveParty(Party p) async {
    _guard();
    try {
      final id = p.id ?? await _db.insert('parties', p.toMap());
      if (p.id != null) await _db.update('parties', p.toMap(), where: 'id=?', whereArgs: [p.id]);
      notify();
      return Party(id: id, type: p.type, name: p.name.trim(), phone: p.phone.trim());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw '«${p.name.trim()}» موجود قبل كده';
      rethrow;
    }
  }

  Future<void> deleteParty(int id) async {
    _guard();
    final used = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM vouchers WHERE party_id=? OR recipient_id=?', [id, id]));
    if ((used ?? 0) > 0) throw 'مينفعش تمسحه لأنه مستخدم في سندات.';
    await _db.delete('parties', where: 'id=?', whereArgs: [id]);
    notify();
  }

  // ---------------- vouchers ----------------
  static const _vSql = '''
    SELECT v.*, w.name AS warehouse_name, p.name AS party_name, r.name AS recipient_name,
      (SELECT COUNT(*) FROM voucher_lines l WHERE l.voucher_id = v.id) AS line_count
    FROM vouchers v
    LEFT JOIN warehouses w ON w.id = v.warehouse_id
    LEFT JOIN parties p ON p.id = v.party_id
    LEFT JOIN parties r ON r.id = v.recipient_id''';

  Future<List<Voucher>> vouchers(VType t, {String q = '', DateTime? from, DateTime? to, int? warehouseId}) async {
    final w = ['v.type = ?'];
    final a = <Object?>[t.key];
    if (warehouseId != null) { w.add('v.warehouse_id = ?'); a.add(warehouseId); }
    if (from != null) { w.add('v.date >= ?'); a.add(dbDate(from)); }
    if (to != null) { w.add('v.date <= ?'); a.add(dbDate(to)); }
    if (q.trim().isNotEmpty) {
      final like = '%${q.trim()}%';
      w.add('''(p.name LIKE ? OR r.name LIKE ? OR v.ref_no LIKE ? OR v.license_no LIKE ? OR CAST(v.number AS TEXT) = ? OR EXISTS(
        SELECT 1 FROM voucher_lines l2 JOIN items i ON i.id = l2.item_id
        WHERE l2.voucher_id = v.id AND $_itemLike))''');
      a.addAll([like, like, like, like, q.trim(), ..._likeArgs(q)]);
    }
    final rows = await _db.rawQuery('$_vSql WHERE ${w.join(' AND ')} ORDER BY v.date DESC, v.number DESC', a);
    return _withTotals(rows.map(Voucher.fromMap).toList());
  }

  Future<List<Voucher>> _withTotals(List<Voucher> list) async {
    final f = await fifo();
    final links = await _db.rawQuery('SELECT id, voucher_id FROM voucher_lines');
    final total = <int, LineCost>{};
    for (final m in links) {
      final v = m['voucher_id'] as int;
      total[v] = (total[v] ?? LineCost.none) + (f.costs[m['id'] as int] ?? LineCost.none);
    }
    return [for (final v in list) v.withTotals(total[v.id]?.value ?? 0, total[v.id]?.missing ?? false)];
  }

  Future<Voucher> voucher(int id) async {
    final h = await _db.rawQuery('$_vSql WHERE v.id = ?', [id]);
    if (h.isEmpty) throw 'السند مش موجود';
    final lines = await _db.rawQuery('''
      SELECT i.*, l.id AS line_id, l.qty, l.note, l.price AS line_price FROM voucher_lines l JOIN items i ON i.id = l.item_id
      WHERE l.voucher_id = ? ORDER BY l.id''', [id]);
    final f = await fifo();
    final parsed = lines
        .map((m) => VoucherLine(Item.fromMap(m), (m['qty'] as num).toDouble(), m['note'] as String, (m['line_price'] as num?)?.toDouble(),
            f.costs[m['line_id'] as int] ?? LineCost.none))
        .toList();
    final all = parsed.fold(LineCost.none, (a, l) => a + l.cost);
    return Voucher.fromMap(h.first, parsed).withTotals(all.value, all.missing);
  }

  Future<int> saveVoucher(Voucher v) async {
    _guard();
    if (v.id != null) {
      final old = await _db.query('vouchers', columns: ['transfer_id'], where: 'id = ?', whereArgs: [v.id]);
      if (old.isNotEmpty && old.first['transfer_id'] != null) throw 'ده تحويل بين المخازن، مينفعش يتعدل من هنا.\nامسحه واعمل تحويل جديد بالكميات الصح.';
    }
    final id = await _db.transaction((tx) => _saveVoucher(tx, v));
    notify();
    return id;
  }

  Future<int> _saveVoucher(Transaction tx, Voucher v) async {
    final wh = v.warehouseId == 0 ? currentWarehouseId : v.warehouseId;
    if (wh == 0) throw 'اختار المخزن';
    final header = {
      'type': v.type.key,
      'warehouse_id': wh,
      'date': dbDate(v.date),
      'party_id': v.partyId,
      'recipient_id': v.recipientId,
      'ref_no': v.refNo.trim(),
      'license_no': v.licenseNo.trim(),
      'notes': v.notes.trim(),
      'attachment': v.attachment,
    };
    int id;
    if (v.id == null) {
      // numbering is per (type, warehouse), so each warehouse has its own sequence
      final n = await tx.rawQuery('SELECT COALESCE(MAX(number), 0) + 1 AS n FROM vouchers WHERE type = ? AND warehouse_id = ?', [v.type.key, wh]);
      id = await tx.insert('vouchers', {...header, 'number': n.first['n'], 'created_at': DateTime.now().toIso8601String()});
    } else {
      id = v.id!;
      await tx.update('vouchers', header, where: 'id=?', whereArgs: [id]);
      await tx.delete('voucher_lines', where: 'voucher_id=?', whereArgs: [id]);
    }
    for (final l in v.lines) {
      await tx.insert('voucher_lines', {'voucher_id': id, 'item_id': l.item.id, 'qty': l.qty, 'note': l.note.trim(), 'price': v.type.isIn ? l.price : null});
    }
    return id;
  }

  /// Lowest balance of an item in a warehouse from [date] onwards (end of each day).
  /// Taking more than this on [date] would leave the warehouse short on that day or later.
  Future<double> availableOn(int itemId, int warehouseId, DateTime date) async {
    final rows = await _db.rawQuery('''
      SELECT v.date AS d, SUM(CASE WHEN v.type='in' THEN l.qty ELSE -l.qty END) AS n
      FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id
      WHERE l.item_id = ? AND v.warehouse_id = ?
      GROUP BY v.date ORDER BY v.date''', [itemId, warehouseId]);
    final day = dbDate(date);
    var run = 0.0, low = double.infinity;
    var before = true;
    for (final r in rows) {
      if (before && (r['d'] as String).compareTo(day) > 0) {
        low = run; // the balance on [date] itself
        before = false;
      }
      run += (r['n'] as num).toDouble();
      if (!before && run < low) low = run;
    }
    return before ? run : low;
  }

  /// Names of items whose balance would go negative if this receipt had [newQty] instead
  /// of its current quantities (empty map = the receipt is deleted). Scoped to its warehouse.
  Future<List<String>> receiptConflicts(Voucher old, Map<int, double> newQty) async {
    final out = <String>[];
    final oldQty = <int, double>{};
    for (final l in old.lines) {
      oldQty[l.item.id!] = (oldQty[l.item.id!] ?? 0) + l.qty;
    }
    for (final l in old.lines) {
      final id = l.item.id!;
      final q = newQty[id] ?? 0;
      if (q < oldQty[id]! && await balance(id, warehouseId: old.warehouseId, excludeVoucher: old.id) + q < -1e-9 && !out.contains(l.item.title)) out.add(l.item.title);
    }
    return out;
  }

  /// Other receipts in the same warehouse already carrying this invoice number.
  Future<List<Voucher>> receiptsWithRef(String ref, int warehouseId, {int? excludeId}) async {
    final rows = await _db.rawQuery(
        "$_vSql WHERE v.type = 'in' AND v.warehouse_id = ? AND v.ref_no = ? COLLATE NOCASE AND v.id <> ? ORDER BY v.date DESC",
        [warehouseId, ref.trim(), excludeId ?? -1]);
    return rows.map(Voucher.fromMap).toList();
  }

  /// Loads parsed inbound vouchers into [warehouseId], creating any missing
  /// suppliers and items. Returns counts for the summary.
  Future<Map<String, int>> importVouchers(List<ImportVoucher> vs, int warehouseId) async {
    _guard();
    final byCode = <String, Item>{};
    final byName = <String, Item>{};
    for (final it in await allItems()) {
      if (it.code.isNotEmpty) byCode[it.code.toLowerCase()] = it;
      if (it.hasAr) byName[it.nameAr.trim().toLowerCase()] = it;
      byName[it.name.toLowerCase()] = it;
    }
    final sups = <String, Party>{for (final p in await parties([PartyType.supplier])) p.name.toLowerCase(): p};
    var vouchers = 0, lines = 0, newItems = 0, newSuppliers = 0;
    for (final v in vs) {
      final sk = v.supplier.toLowerCase();
      var sup = sups[sk];
      if (sup == null) {
        sup = await saveParty(Party(type: PartyType.supplier, name: v.supplier));
        sups[sk] = sup;
        newSuppliers++;
      }
      final vl = <VoucherLine>[];
      for (final r in v.lines) {
        Item? it = r.code.isNotEmpty ? byCode[r.code.toLowerCase()] : null;
        it ??= byName[r.name.toLowerCase()];
        if (it == null) {
          it = await saveItem(Item(name: r.name, code: r.code, unit: r.unit.isEmpty ? 'قطعة' : r.unit, price: r.price));
          if (it.code.isNotEmpty) byCode[it.code.toLowerCase()] = it;
          if (it.hasAr) byName[it.nameAr.toLowerCase()] = it;
          byName[it.name.toLowerCase()] = it;
          newItems++;
        }
        vl.add(VoucherLine(it, r.qty, '', r.price));
      }
      await saveVoucher(Voucher(
          type: VType.inbound, warehouseId: warehouseId, date: v.date, partyId: sup.id, refNo: v.ref, licenseNo: v.license, lines: vl));
      vouchers++;
      lines += vl.length;
    }
    notify();
    return {'vouchers': vouchers, 'lines': lines, 'newItems': newItems, 'newSuppliers': newSuppliers};
  }

  /// Moves items from one warehouse to another: an issue from the source and a
  /// receipt into the destination, saved together and linked so deleting one removes
  /// both. The receipt isn't given a price: FIFO hands it the exact price layers the
  /// issue took at the source, so value is preserved and follows later corrections.
  Future<void> transfer(
      {required int fromWh, required int toWh, required DateTime date, required List<MapEntry<Item, double>> lines, String notes = ''}) async {
    _guard();
    if (fromWh == toWh) throw 'لازم تختار مخزنين مختلفين';
    // the same item twice becomes one line
    final merged = <int, MapEntry<Item, double>>{};
    for (final e in lines) {
      if (e.value.isNaN || e.value < 0) throw 'الكمية غلط: ${e.key.title}';
      final old = merged[e.key.id!];
      merged[e.key.id!] = MapEntry(e.key, (old?.value ?? 0) + e.value);
    }
    final clean = merged.values.where((e) => e.value > 1e-9).toList();
    if (clean.isEmpty) throw 'ضيف صنف واحد على الأقل بكمية';
    for (final e in clean) {
      final item = e.key, qty = e.value;
      final avail = await availableOn(item.id!, fromWh, date);
      if (qty > avail + 1e-6) {
        final now = await balance(item.id!, warehouseId: fromWh);
        throw now + 1e-6 >= qty
            ? 'الكمية أكبر من رصيد المصدر في تاريخ ${fmtDate(date)}: ${item.title}\nالمتاح وقتها ${fmtQty(avail < 0 ? 0 : avail)} ${item.unit}. غيّر تاريخ التحويل لتاريخ بعد الاستلام.'
            : 'الكمية أكبر من رصيد المصدر: ${item.title}\nالمتاح ${fmtQty(now < 0 ? 0 : now)} ${item.unit}';
      }
    }
    final fromName = (await warehouse(fromWh))?.name ?? '';
    final toName = (await warehouse(toWh))?.name ?? '';
    final extra = notes.trim().isEmpty ? '' : ' - ${notes.trim()}';
    await _db.transaction((tx) async {
      final outId = await _saveVoucher(tx,
          Voucher(type: VType.outbound, warehouseId: fromWh, date: date, notes: 'تحويل إلى: $toName$extra', lines: [for (final e in clean) VoucherLine(e.key, e.value)]));
      final inId = await _saveVoucher(tx,
          Voucher(type: VType.inbound, warehouseId: toWh, date: date, notes: 'تحويل من: $fromName$extra', lines: [for (final e in clean) VoucherLine(e.key, e.value)]));
      await tx.update('vouchers', {'transfer_id': outId}, where: 'id IN (?, ?)', whereArgs: [outId, inId]);
    });
    notify();
  }

  Future<void> deleteVoucher(int id) async {
    _guard();
    final v = await voucher(id);
    // a transfer is two linked vouchers; deleting one deletes both
    final ids = <int>[id];
    if (v.transferId != null) {
      final sib = await _db.query('vouchers', columns: ['id'], where: 'transfer_id = ? AND id <> ?', whereArgs: [v.transferId, id]);
      ids.addAll(sib.map((e) => e['id'] as int));
    }
    for (final vid in ids) {
      final vv = await voucher(vid);
      if (vv.type.isIn) {
        final bad = await receiptConflicts(vv, const {});
        if (bad.isNotEmpty) {
          throw '${v.isTransfer ? 'مينفعش تمسح التحويل' : 'مينفعش تمسح السند'}: اتصرف من البضاعة والرصيد هيبقى بالسالب:\n${bad.join('، ')}\nامسح أو عدّل إذن الصرف الأول.';
        }
      }
    }
    for (final vid in ids) {
      final vv = await voucher(vid);
      await _db.delete('vouchers', where: 'id=?', whereArgs: [vid]);
      if (vv.attachment != null) {
        final fl = File(vv.attachment!);
        if (await fl.exists()) await fl.delete();
      }
    }
    notify();
  }

  // ---------------- reports & home ----------------
  Future<List<MovementRow>> movements(
          {DateTime? from, DateTime? to, VType? type, int? partyId, int? recipientId, int? warehouseId, String ref = '', String q = ''}) async =>
      _moves(await fifo(), from: from, to: to, type: type, partyId: partyId, recipientId: recipientId, warehouseId: warehouseId, ref: ref, q: q);

  /// Movement lines (newest first), valued with the given FIFO result.
  Future<List<MovementRow>> _moves(FifoResult f,
      {DateTime? from, DateTime? to, VType? type, int? partyId, int? recipientId, int? warehouseId, String ref = '', String q = ''}) async {
    final w = <String>['1 = 1'];
    final a = <Object?>[];
    if (warehouseId != null) { w.add('v.warehouse_id = ?'); a.add(warehouseId); }
    if (from != null) { w.add('v.date >= ?'); a.add(dbDate(from)); }
    if (to != null) { w.add('v.date <= ?'); a.add(dbDate(to)); }
    if (type != null) { w.add('v.type = ?'); a.add(type.key); }
    if (partyId != null) { w.add('v.party_id = ?'); a.add(partyId); }
    if (recipientId != null) { w.add('v.recipient_id = ?'); a.add(recipientId); }
    if (ref.trim().isNotEmpty) { w.add('v.ref_no LIKE ?'); a.add('%${ref.trim()}%'); }
    if (q.trim().isNotEmpty) { w.add(_itemLike); a.addAll(_likeArgs(q)); }
    final rows = await _db.rawQuery('''
      SELECT i.*, v.id AS vid, v.type AS vtype, v.number, v.date, v.ref_no, v.notes AS vnotes, v.transfer_id AS tid,
        p.name AS party_name, rc.name AS recipient_name, l.qty, l.id AS line_id
      FROM voucher_lines l
      JOIN vouchers v ON v.id = l.voucher_id
      JOIN items i ON i.id = l.item_id
      LEFT JOIN parties p ON p.id = v.party_id
      LEFT JOIN parties rc ON rc.id = v.recipient_id
      WHERE ${w.join(' AND ')}
      ORDER BY v.date DESC, $_rank DESC, v.id DESC, l.id''', a);
    return rows
        .map((m) => MovementRow(m['vid'] as int, m['number'] as int, Item.fromMap(m), VType.of(m['vtype'] as String),
            DateTime.parse(m['date'] as String), (m['party_name'] as String?) ?? '', (m['recipient_name'] as String?) ?? '', m['ref_no'] as String,
            (m['qty'] as num).toDouble(), f.costs[m['line_id'] as int] ?? LineCost.none,
            m['tid'] == null ? '' : _transferLabel(m['vnotes'] as String)))
        .toList();
  }

  /// For each item in one warehouse: balance before [from], the receipts and issues
  /// inside the period (with supplier / site and FIFO prices), and what is left at
  /// the end by price. Valued with FIFO as it stood on [to], so the closing value
  /// always equals the value of the layers left.
  Future<List<BalanceRow>> balanceReport({DateTime? from, DateTime? to, String q = '', int? warehouseId}) async {
    final wh = warehouseId ?? currentWarehouseId;
    final f = from == null ? '0000-01-01' : dbDate(from);
    final t = to == null ? '9999-12-31' : dbDate(to);
    final rows = await _db.rawQuery('''
      SELECT i.*,
        COALESCE(SUM(CASE WHEN v.date < ? THEN (CASE WHEN v.type='in' THEN l.qty ELSE -l.qty END) END), 0) AS opening,
        COALESCE(SUM(CASE WHEN v.type='in'  AND v.date >= ? AND v.date <= ? THEN l.qty END), 0) AS in_qty,
        COALESCE(SUM(CASE WHEN v.type='out' AND v.date >= ? AND v.date <= ? THEN l.qty END), 0) AS out_qty,
        COUNT(CASE WHEN v.date <= ? THEN v.id END) AS n
      FROM items i
      LEFT JOIN voucher_lines l ON l.item_id = i.id
      LEFT JOIN vouchers v ON v.id = l.voucher_id AND v.warehouse_id = ?
      WHERE $_itemLike
      GROUP BY i.id HAVING n > 0 ORDER BY $_order''', [f, f, t, f, t, t, wh, ..._likeArgs(q)]);
    final cost = await fifo(until: to);
    final lines = await _db.rawQuery(
        'SELECT l.id, l.item_id, v.type, v.date FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id WHERE v.warehouse_id = ? AND v.date <= ?', [wh, t]);
    final open = <int, double>{}, inV = <int, double>{}, outV = <int, double>{};
    final missing = <int>{};
    for (final l in lines) {
      final item = l['item_id'] as int;
      final date = l['date'] as String;
      final c = cost.costs[l['id'] as int] ?? LineCost.none;
      final isIn = l['type'] == 'in';
      if (c.missing) missing.add(item);
      if (date.compareTo(f) < 0) {
        open[item] = (open[item] ?? 0) + (isIn ? c.value : -c.value);
      } else if (isIn) {
        inV[item] = (inV[item] ?? 0) + c.value;
      } else {
        outV[item] = (outV[item] ?? 0) + c.value;
      }
    }
    final moves = <int, List<MovementRow>>{};
    for (final m in (await _moves(cost, from: from, to: to, warehouseId: wh, q: q)).reversed) {
      moves.putIfAbsent(m.itemId, () => []).add(m);
    }
    return rows
        .map((m) {
          final id = m['id'] as int;
          return BalanceRow(Item.fromMap(m), (m['opening'] as num).toDouble(), (m['in_qty'] as num).toDouble(), (m['out_qty'] as num).toDouble(),
              open[id] ?? 0, inV[id] ?? 0, outV[id] ?? 0, missing.contains(id), moves[id] ?? const [], cost.remaining[(wh, id)] ?? LineCost.none);
        })
        // nothing before the period and nothing in it: not part of this report
        .where((b) => b.opening.abs() > 1e-9 || b.moves.isNotEmpty || b.openingValue.abs() > 1e-9)
        .toList();
  }

  Future<HomeStats> homeStats({int? warehouseId}) async {
    final wh = warehouseId ?? currentWarehouseId;
    final st = await stock(warehouseId: wh);
    final c = await _db.rawQuery(
        'SELECT type, COUNT(*) AS n FROM vouchers WHERE date = ? AND warehouse_id = ? GROUP BY type', [dbDate(today()), wh]);
    int count(String k) => c.where((r) => r['type'] == k).map((r) => r['n'] as int).firstOrNull ?? 0;
    final recent = await _withTotals(
        (await _db.rawQuery('$_vSql WHERE v.warehouse_id = ? ORDER BY v.created_at DESC LIMIT 8', [wh])).map(Voucher.fromMap).toList());
    return HomeStats(st.length, count('in'), count('out'), st.where((s) => s.low).toList(), recent, st.fold(0.0, (a, s) => a + s.value));
  }

  // ---------------- settings ----------------
  Future<String> setting(String key, [String def = '']) async {
    final r = await _db.query('settings', where: 'key=?', whereArgs: [key]);
    return r.isEmpty ? def : r.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
