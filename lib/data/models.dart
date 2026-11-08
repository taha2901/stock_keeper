enum PartyType {
  supplier('supplier', 'المورد', 'الموردين'),
  site('site', 'الموقع', 'المواقع'),
  recipient('recipient', 'المستلم', 'المستلمين');

  const PartyType(this.key, this.label, this.plural);
  final String key, label, plural;
  static PartyType of(String k) => values.firstWhere((e) => e.key == k);
}

enum VType {
  inbound('in', 'وارد', 'سند استلام'),
  outbound('out', 'صادر', 'إذن صرف');

  const VType(this.key, this.label, this.doc);
  final String key, label, doc;
  bool get isIn => this == inbound;
  PartyType get partyType => isIn ? PartyType.supplier : PartyType.site;
  static VType of(String k) => values.firstWhere((e) => e.key == k);
}

const units = [
  'قطعة', 'متر', 'طن', 'كيلو', 'لتر', 'متر مربع', 'متر مكعب',
  'لفة', 'كرتونة', 'شيكارة', 'طقم', 'علبة', 'عدد',
];

class Warehouse {
  final int? id;
  final String name;
  const Warehouse({this.id, required this.name});
  factory Warehouse.fromMap(Map<String, Object?> m) => Warehouse(id: m['id'] as int, name: m['name'] as String);
  Map<String, Object?> toMap() => {'name': name.trim()};
}

class Item {
  final int? id;
  final String name, nameEn, code, unit;
  final double minQty;

  /// Suggested price, pre-filled on receipts. FIFO only ever uses the price saved on the receipt.
  final double? price;

  const Item({this.id, required this.name, this.nameEn = '', this.code = '', this.unit = 'قطعة', this.minQty = 0, this.price});

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as int,
        name: m['name'] as String,
        nameEn: m['name_en'] as String,
        code: m['code'] as String,
        unit: m['unit'] as String,
        minQty: (m['min_qty'] as num).toDouble(),
        price: (m['price'] as num?)?.toDouble(),
      );

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'name_en': nameEn.trim(),
        'code': code.trim(),
        'unit': unit.trim().isEmpty ? 'قطعة' : unit.trim(),
        'min_qty': minQty,
        'price': price,
      };

  /// Secondary line shown under the item name (English name / supplier code).
  String get extra => [code, nameEn].where((e) => e.isNotEmpty).join(' • ');
}

/// Part of a line valued at one price. A null price means no price was entered.
class CostSlice {
  final double qty;
  final double? price;
  const CostSlice(this.qty, this.price);
  double get value => qty * (price ?? 0);
}

/// A line's FIFO value: one slice per purchase price it was taken from.
class LineCost {
  final List<CostSlice> slices;
  const LineCost(this.slices);
  static const none = LineCost([]);
  double get value => slices.fold(0.0, (a, s) => a + s.value);
  double get unpriced => slices.where((s) => s.price == null).fold(0.0, (a, s) => a + s.qty);
  bool get missing => unpriced > 0;
  LineCost operator +(LineCost o) => LineCost([...slices, ...o.slices]);
}

class ItemStock {
  final Item item;
  final double inQty, outQty, value;
  final bool missing;
  const ItemStock(this.item, this.inQty, this.outQty, [this.value = 0, this.missing = false]);
  double get balance => (inQty - outQty).abs() < 1e-6 ? 0 : inQty - outQty;
  bool get low => balance < 0 || (item.minQty > 0 && balance <= item.minQty);
}

class Party {
  final int? id;
  final PartyType type;
  final String name, phone;
  const Party({this.id, required this.type, required this.name, this.phone = ''});

  factory Party.fromMap(Map<String, Object?> m) => Party(
      id: m['id'] as int, type: PartyType.of(m['type'] as String), name: m['name'] as String, phone: m['phone'] as String);

  Map<String, Object?> toMap() => {'type': type.key, 'name': name.trim(), 'phone': phone.trim()};
}

class VoucherLine {
  final Item item;
  final double qty;
  final String note;
  final double? price;
  final LineCost cost;
  const VoucherLine(this.item, this.qty, [this.note = '', this.price, this.cost = LineCost.none]);
}

class Voucher {
  final int? id;
  final VType type;
  final int number;
  final DateTime date;
  final int warehouseId;
  final int? partyId, recipientId;
  final String warehouseName, partyName, recipientName, refNo, licenseNo, notes;
  final String? attachment;
  final int? transferId;
  final List<VoucherLine> lines;
  final int lineCount;
  final double total;
  final bool missing;

  const Voucher({
    this.id,
    required this.type,
    this.number = 0,
    required this.date,
    this.warehouseId = 0,
    this.warehouseName = '',
    this.partyId,
    this.partyName = '',
    this.recipientId,
    this.recipientName = '',
    this.refNo = '',
    this.licenseNo = '',
    this.notes = '',
    this.attachment,
    this.transferId,
    this.lines = const [],
    this.lineCount = 0,
    this.total = 0,
    this.missing = false,
  });

  factory Voucher.fromMap(Map<String, Object?> m, [List<VoucherLine> lines = const []]) => Voucher(
        id: m['id'] as int,
        type: VType.of(m['type'] as String),
        number: m['number'] as int,
        date: DateTime.parse(m['date'] as String),
        warehouseId: (m['warehouse_id'] as int?) ?? 0,
        warehouseName: (m['warehouse_name'] as String?) ?? '',
        partyId: m['party_id'] as int?,
        partyName: (m['party_name'] as String?) ?? '',
        recipientId: m['recipient_id'] as int?,
        recipientName: (m['recipient_name'] as String?) ?? '',
        refNo: m['ref_no'] as String,
        licenseNo: (m['license_no'] as String?) ?? '',
        notes: m['notes'] as String,
        attachment: m['attachment'] as String?,
        transferId: m['transfer_id'] as int?,
        lines: lines,
        lineCount: (m['line_count'] as int?) ?? lines.length,
      );

  String get title => '${type.doc} رقم $number';
  bool get isTransfer => transferId != null;

  Voucher withTotals(double total, bool missing) => Voucher(
        id: id, type: type, number: number, date: date, warehouseId: warehouseId, warehouseName: warehouseName, partyId: partyId, partyName: partyName,
        recipientId: recipientId, recipientName: recipientName, refNo: refNo, licenseNo: licenseNo, notes: notes,
        attachment: attachment, transferId: transferId, lines: lines, lineCount: lineCount, total: total, missing: missing,
      );
}

class LedgerRow {
  final int voucherId, number;
  final VType type;
  final DateTime date;
  final String party, refNo;
  final double qty, balance, stockValue;
  final LineCost cost;
  const LedgerRow(this.voucherId, this.number, this.type, this.date, this.party, this.refNo, this.qty, this.balance, this.cost, this.stockValue);
}

class MovementRow {
  final int voucherId, number, itemId;
  final VType type;
  final DateTime date;
  final String item, unit, party, recipient, refNo;
  final double qty;
  final LineCost cost;
  const MovementRow(this.voucherId, this.number, this.itemId, this.type, this.date, this.item, this.unit, this.party, this.recipient, this.refNo, this.qty, this.cost);
}

/// One item summed over a filtered set of movements.
class GroupRow {
  final String item, unit;
  final double total, value;
  final int times;
  final DateTime last;
  final bool missing;
  const GroupRow(this.item, this.unit, this.total, this.times, this.last, this.value, this.missing);
}

/// One supplier / site summed over a filtered set of movements.
class PartyTotal {
  final String party;
  final int vouchers, lines;
  final double value;
  final bool missing;
  const PartyTotal(this.party, this.vouchers, this.lines, this.value, this.missing);
}

/// One item in the balance report for a period.
class BalanceRow {
  final Item item;
  final double opening, inQty, outQty, openingValue, inValue, outValue;
  final bool missing;
  const BalanceRow(this.item, this.opening, this.inQty, this.outQty, this.openingValue, this.inValue, this.outValue, this.missing);
  double get closing {
    final v = opening + inQty - outQty;
    return v.abs() < 1e-6 ? 0 : v;
  }

  double get closingValue => openingValue + inValue - outValue;
}

class HomeStats {
  final int items, todayIn, todayOut;
  final List<ItemStock> low;
  final List<Voucher> recent;
  final double stockValue;
  const HomeStats(this.items, this.todayIn, this.todayOut, this.low, this.recent, this.stockValue);
}

/// One row read from an imported Excel sheet.
/// One inbound voucher parsed from an uploaded Excel file.
class ImportVoucher {
  final String supplier, ref, license;
  final DateTime date;
  final List<ImportRow> lines;
  const ImportVoucher({required this.supplier, required this.date, this.ref = '', this.license = '', this.lines = const []});
  int get lineCount => lines.length;
}

class ImportRow {
  final String name, unit, note;
  final double qty;
  final double? price;
  final String code;
  const ImportRow(this.name, this.qty, [this.unit = '', this.note = '', this.price, this.code = '']);
}
