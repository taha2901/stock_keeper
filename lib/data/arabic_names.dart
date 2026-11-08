/// Builds the Arabic name of a supplier item from its English description,
/// in the wording the site already uses (the «الوارد - المنفذ» sheet):
///   OD:110mm HDPE EF COUPLER SDR11 [ACUP110.16]  ->  جلبة EF قطر 110مم
///
/// Nothing here guesses loosely: a description that isn't recognised gets no
/// suggestion and the keeper types it by hand. Two different items never get
/// the same Arabic name ([uniqueAll] adds the detail that tells them apart).
class ArabicNames {
  ArabicNames._();

  static final _arabic = RegExp(r'[؀-ۿ]');
  static bool isArabic(String s) => _arabic.hasMatch(s);

  static String _num(String v) => v.contains('.') ? v.replaceFirst(RegExp(r'\.?0+$'), '') : v;

  /// Upper-cased description without the [CODE] part, padded with spaces so
  /// patterns can match whole words at the edges.
  static String _clean(String s) => ' ${s.toUpperCase().replaceAll(RegExp(r'\[[^\]]*\]'), ' ').replaceAll('×', 'X').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

  /// Diameters in mm, outer size first: "OD:160-110mm" -> [160, 110].
  static List<String> _dims(String u) {
    final od = RegExp(r'OD\s*:?\s*(\d+(?:\.\d+)?(?:\s*(?:MM)?\s*[-X*/]\s*\d+(?:\.\d+)?)*)\s*MM').firstMatch(u);
    if (od != null) return RegExp(r'\d+(?:\.\d+)?').allMatches(od[1]!).map((m) => _num(m[0]!)).toList();
    final dim = RegExp(r'DIM\s*(\d+(?:\s*[X*]\s*\d+)*)').firstMatch(u);
    if (dim != null) return RegExp(r'\d+').allMatches(dim[1]!).map((m) => m[0]!).toList();
    final dn = RegExp(r'\bDN\s*(\d+)').firstMatch(u);
    if (dn != null) return [dn[1]!];
    final mm = RegExp(r'(\d+(?:\.\d+)?)\s*MM\b').firstMatch(u);
    return mm == null ? const [] : [_num(mm[1]!)];
  }

  /// "قطر 110مم", "قطر 160x110 مم" (a space keeps the numbers in order in the PDF).
  static String _size(List<String> d) => d.isEmpty ? '' : 'قطر ${_flat(d)}';
  static String _flat(List<String> d) => d.isEmpty ? '' : (d.length == 1 ? '${d.first}مم' : '${d.join('x')} مم');

  static String _join(List<String> parts) => parts.where((p) => p.isNotEmpty).join(' ');

  /// Bumped whenever the rules learn new items: items still without an Arabic
  /// name are filled again once on the next start.
  static const version = 2;

  /// Inch sizes: 3/4" -> "3/4 بوصة".
  static String? _inch(String u) {
    final m = RegExp(r'(\d+(?:\s*\d+)?/\d+|\d+(?:\.\d+)?)\s*(?:"|' "''" r'|INCH(?:ES)?\b|IN\b)').firstMatch(u);
    return m == null ? null : '${m[1]!.replaceAll(RegExp(r'\s+'), ' ')} بوصة';
  }

  /// The Arabic name for [english], or '' when it isn't recognised.
  static String suggest(String english) {
    if (english.trim().isEmpty || isArabic(english)) return '';
    final u = _clean(english);
    final s = _suggest(u);
    return s.isNotEmpty && RegExp(r'\bUSED\b').hasMatch(u) ? '$s (مستعمل)' : s;
  }

  static String _suggest(String u) {
    bool has(String p) => RegExp(p).hasMatch(u);
    final d = _dims(u);
    String? num(String re) => RegExp(re).firstMatch(u)?[1];

    // ---- valves and their accessories (sizes are DN = the PDF's "قطر") ----
    if (has(r'SPINDLE')) {
      final valve = RegExp(r'FOR\s*(\d+)\s*MM').firstMatch(u)?[1] ?? RegExp(r'\bDN\s*(\d+)').firstMatch(u)?[1];
      final cm = RegExp(r'(\d+)\s*CM\b').firstMatch(u)?[1];
      final mm = RegExp(r'SPINDLE\s*(?:LENGTH\s*)?(\d+)\s*MM').firstMatch(u)?[1];
      final len = cm != null ? '$cm سم' : (mm != null ? '$mm مم' : '');
      return _join(['عمود تطويل', if (valve != null) 'لمحبس ${_size([valve])}', if (len.isNotEmpty) '- طول $len']);
    }
    String valve(String kind) => _join([kind, d.isNotEmpty ? _size(d) : (_inch(u) ?? '')]);
    if (has(r'GATE\s*VALVE|SLUICE\s*VALVE')) return valve('محبس');
    if (has(r'BUTTERFLY')) return valve('محبس فراشة');
    if (has(r'AIR (RELEASE )?VALVE|AIR VALVE')) return valve('محبس هواء');
    if (has(r'CHECK VALVE|NON.?RETURN')) return valve('محبس عدم رجوع');
    if (has(r'BALL VALVE')) return valve('محبس كروي');
    if (has(r'HYDRANT')) return 'طفايات حريق';
    if (has(r'VALVE BOX|SURFACE BOX')) return 'صندوق محبس';

    // ---- bolts: "BOLT NUT & WASHER 16X100" -> مجموعة مسامير 100مم ----
    if (has(r'\bBOLTS?\b|\bNUTS?\b|\bWASHERS?\b')) {
      final m = RegExp(r'M?(\d+)\s*X\s*(\d+)').firstMatch(u);
      return m == null ? 'مجموعة مسامير' : 'مجموعة مسامير ${m[2]}مم';
    }

    // ---- electrical and site consumables ----
    if (has(r'TAPE')) {
      if (has(r'ELECTRIC')) return 'شريط كهرباء';
      if (has(r'WARN')) return 'شريط تحذيري';
      if (has(r'TEFLON|PTFE')) return 'شريط تفلون';
      if (has(r'DENSO|WRAP')) return 'شريط تغليف';
      if (has(r'DUCT|ADHESIVE')) return 'شريط لاصق';
      if (has(r'MEASUR')) return 'شريط قياس (متر)';
      return '';
    }
    if (has(r'ELECTRIC') && has(r'SOCKET')) return 'فيشة كهرباء';
    if (has(r'EXTENSION (CABLE|CORD|WIRE|REEL)')) return 'وصلة كهرباء';

    // ---- site, safety and office items ----
    if (has(r'\bVESTS?\b')) {
      return _join(['سترة سلامة', if (has(r'ENGR|ENGINEER')) 'للمهندسين', if (has(r'LABOU?R|WORKER')) 'للعمال']);
    }
    if (has(r'HELMET|HARD ?HAT')) return 'خوذة سلامة';
    if (has(r'GLOVE')) return 'جوانتي';
    if (has(r'SAFETY (SHOE|BOOT)|\bBOOTS?\b')) return 'حذاء سلامة';
    if (has(r'GOGGLE|SAFETY GLASS')) return 'نظارة سلامة';
    if (has(r'\bMASKS?\b')) return 'كمامة';
    if (has(r'EXTINGUISHER')) return 'طفاية حريق يدوية';
    if (has(r'NEW\s*JERSE?Y')) {
      final m = num(r'(\d+(?:\.\d+)?)\s*(?:MTRS?|METERS?|M)\b');
      return _join(['حاجز نيوجيرسي', if (has(r'PLASTIC')) 'بلاستيك', if (has(r'CONCRETE')) 'خرساني', if (m != null) '$m متر']);
    }
    if (has(r'\bCONES?\b')) return 'قمع مرور';
    if (has(r'SIGN\s*BOARD|\bSIGNS?\b')) return has(r'PROJECT') ? 'لوحة المشروع' : 'لوحة إرشادية';
    if (has(r'\bTABLE\b|\bDESK\b')) {
      final cm = num(r'(\d+)\s*CM\b');
      return _join([has(r'OFFICE|DESK') ? 'مكتب' : 'طاولة', if (has(r'WOOD')) 'خشب', if (has(r'EXTENSION')) 'بامتداد', if (cm != null) '$cm سم']);
    }
    if (has(r'\bCHAIRS?\b')) return _join(['كرسي', if (has(r'OFFICE')) 'مكتب', if (has(r'PLASTIC')) 'بلاستيك']);
    if (has(r'WATER COOLER|COOLER')) return 'كولر مياه';
    if (has(r'GENERATOR')) return 'مولد كهرباء';
    if (has(r'WATER METER')) return _join(['عداد مياه', d.isNotEmpty ? _size(d) : (_inch(u) ?? '')]);
    if (has(r'GREASE')) return 'شحم';
    if (has(r'THINNER')) return 'تنر';
    if (has(r'PRIMER')) return 'برايمر';
    if (has(r'BRUSH')) return 'فرشاة دهان';
    if (has(r'PAINT')) {
      return _join(['دهان', if (has(r'ACR[YA]LIC')) 'أكريليك', if (has(r'\bOIL')) 'زيتي', if (has(r'SPRAY')) 'سبراي', if (has(r'ROAD|MARKING')) 'تخطيط طرق']);
    }
    if (has(r'SILICON')) return 'سيليكون';
    if (has(r'SOLVENT CEMENT|PVC GLUE|\bGLUE\b')) return 'غراء';
    if (has(r'CEMENT')) return 'أسمنت';
    if (has(r'\bSAND\b')) return 'رمل';
    if (has(r'GRAVEL|AGGREGATE')) return 'بحص';
    if (has(r'PLYWOOD')) return 'خشب أبلكاش';
    if (has(r'\bNAILS?\b')) return 'مسامير خشب';
    if (has(r'\bROPE\b')) return 'حبل';
    if (has(r'\bHOSE\b')) return 'خرطوم';
    if (has(r'SHOVEL')) return 'كوريك';
    if (has(r'WHEEL\s*BARROW')) return 'عربية يد';
    if (has(r'LADDER')) return 'سلم';
    if (has(r'HAMMER')) return 'شاكوش';
    if (has(r'BUCKET')) return 'جردل';

    // ---- fittings ----
    if (has(r'REDUC\w* TEE|TEE REDUC')) {
      // the sheet writes a reducer tee 160-110 as "TEE DIM 160*160*110"
      return d.length >= 2 ? _join(['تي', _size([d[0], d[0], d[1]])]) : _join(['تي', _size(d)]);
    }
    if (has(r'\bTEE\b|^ T ')) {
      return d.length == 1 ? _join(['تي', _size([d[0], d[0], d[0]])]) : _join(['تي', _size(d)]);
    }
    if (has(r'REDUCER|REDUCING')) return _join(['مسلوب', _size(d)]);
    if (has(r'ELBOW|\bBEND\b')) {
      final a = RegExp(r'(\d+(?:\.\d+)?)\s*(?:°|DEG)').firstMatch(u)?[1] ?? RegExp(r'(?:ELBOW|BEND)\s*(\d+(?:\.\d+)?)\b').firstMatch(u)?[1];
      return _join(['كوع', if (a != null) _num(a), _size(d)]);
    }
    if (has(r'COUPL')) return _join(['جلبة', if (has(r'\bEF\b|ELECTRO')) 'EF', _size(d)]);
    // the flange pair: the HDPE adaptor is «فلانشة», the steel backing ring is «رينج»
    if (has(r'FLANGE ADAPT|STUB')) return _join(['فلانشة', _flat(d)]);
    if (has(r'BLIND FLANGE')) return _join(['فلانشة عمياء', _flat(d)]);
    if (has(r'FLANGE|BACKING RING')) return _join(['رينج', _flat(d)]);
    if (has(r'END CAP|\bCAP\b')) return _join(['طبة نهاية', _size(d)]);
    if (has(r'SADDLE')) return _join(['سرج', _size(d)]);
    if (has(r'GASKET')) return _join(['جوان', _size(d)]);
    if (has(r'COIL')) return _join(['مواسير لفة', _size(d)]);
    if (has(r'PIPE')) return _join(['مواسير', _size(d)]);
    if (has(r'MARKER')) return 'علامة إرشادية';
    return '';
  }

  /// Details that can tell two items with the same base name apart.
  static List<String> _details(String english) {
    final u = _clean(english);
    final out = <String>[];
    void add(String re, String Function(Match) f) {
      final m = RegExp(re).firstMatch(u);
      if (m != null) out.add(f(m));
    }

    add(r'\bEF\b', (_) => 'EF');
    add(r'\bBF\b', (_) => 'BF');
    add(r'SDR\s*(\d+(?:\.\d+)?)', (m) => 'SDR${m[1]}');
    add(r'\bPN\s*(\d+)', (m) => 'PN${m[1]}');
    add(r'\bINJ\b|INJECT', (_) => 'حقن');
    add(r'\bFAB\b|FABRICAT', (_) => 'تصنيع');
    add(r'BLUE', (_) => 'خط أزرق');
    add(r'\b(SS\s*\d{3})\b', (m) => m[1]!.replaceAll(' ', ''));
    add(r'(?:BOLTS?|WASHERS?|NUTS?)\b.*?\bM?(\d+)\s*X\s*\d+', (m) => 'M${m[1]}');
    return out;
  }

  /// Suggestions for many items at once, guaranteed distinct from each other and
  /// from [taken] (Arabic names already in use). Items with no suggestion are left out.
  static Map<int, String> uniqueAll(List<({int id, String name, String code})> items, {Set<String> taken = const {}}) {
    final base = <int, String>{};
    for (final it in items) {
      final s = suggest(it.name);
      if (s.isNotEmpty) base[it.id] = s;
    }
    final byId = {for (final it in items) it.id: it};

    // 1) same base name: add only the details that differ inside the group
    final groups = <String, List<int>>{};
    base.forEach((id, s) => groups.putIfAbsent(s, () => []).add(id));
    final out = <int, String>{};
    for (final e in groups.entries) {
      if (e.value.length == 1 && !taken.contains(e.key)) {
        out[e.value.single] = e.key;
        continue;
      }
      final det = {for (final id in e.value) id: _details(byId[id]!.name)};
      final shared = det.values.map((l) => l.toSet()).reduce((a, b) => a.intersection(b));
      for (final id in e.value) {
        final extra = det[id]!.where((x) => (e.value.length == 1 || !shared.contains(x)) && !e.key.contains(x)).toList();
        out[id] = _join([e.key, ...extra]);
      }
    }

    // 2) still clashing (or clashing with a name in use): add the supplier code
    final seen = <String, int>{};
    for (final n in out.values) {
      seen[n] = (seen[n] ?? 0) + 1;
    }
    for (final id in out.keys.toList()) {
      final n = out[id]!;
      if ((seen[n] ?? 0) > 1 || taken.contains(n)) {
        final code = byId[id]!.code.replaceAll(RegExp(r'[\[\]]'), '').trim();
        if (code.isNotEmpty) out[id] = '$n ($code)';
      }
    }

    // 3) last resort, so two items can never share a name
    final used = <String>{...taken};
    for (final id in out.keys.toList()) {
      var n = out[id]!;
      for (var k = 2; used.contains(n); k++) {
        n = '${out[id]!} - $k';
      }
      out[id] = n;
      used.add(n);
    }
    return out;
  }

  /// One new item's suggestion, kept distinct from the names in [taken].
  static String uniqueOne(String name, String code, Set<String> taken) =>
      uniqueAll([(id: 0, name: name, code: code)], taken: taken)[0] ?? '';
}
