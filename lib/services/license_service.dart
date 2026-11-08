import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../data/repo.dart';

/// One-time, offline activation tied to the device.
///
/// First run the app is read-only and shows a device code. The owner turns that
/// code into an activation key (with `tool/keygen.dart`, which holds the same
/// [_secret]) and the keeper types it in once. After that the app is fully usable
/// forever on that device, with no internet and no expiry. Copying the app or its
/// backup to another machine changes the device code, so it returns to read-only
/// until activated again — it never stops or locks the data.
class LicenseService {
  LicenseService._();

  /// CHANGE THIS before you build, and keep the same value in tool/keygen.dart.
  /// Anyone who has this string can generate keys, so don't share it.
  static const _secret = 'SK-IZSJFK-OIFXBZ-K1JE08-NDE15X-WZU47N';

  static const _base32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford, no I L O U

  static bool activated = false; // loaded at startup, also gates every write

  static String _group(String s, int size) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && i % size == 0) b.write('-');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _b32(List<int> bytes, int chars) {
    var bits = 0, value = 0;
    final out = StringBuffer();
    for (final byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5 && out.length < chars) {
        out.write(_base32[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
      if (out.length >= chars) break;
    }
    return out.toString();
  }

  /// Stable per machine. Windows: the OS MachineGuid (survives app reinstall,
  /// changes on a different PC). Otherwise a random id kept in the database.
  static Future<String> _deviceId() async {
    if (Platform.isWindows) {
      try {
        final r = await Process.run('reg', [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ]);
        final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)').firstMatch('${r.stdout}');
        if (m != null) return 'win:${m.group(1)}';
      } catch (_) {}
    }
    var id = await Repo.i.setting('device_rand');
    if (id.isEmpty) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await Repo.i.setSetting('device_rand', id);
    }
    return 'gen:$id';
  }

  /// The short code shown to the keeper and read back to the owner.
  static Future<String> deviceCode() async {
    final h = sha256.convert(utf8.encode('device|${await _deviceId()}')).bytes;
    return _group(_b32(h, 12), 4); // e.g. ABCD-EFGH-JKMN
  }

  /// The key the owner gives back. Derived only from the device code, so the
  /// keygen tool needs just that code — never the raw machine id.
  static String keyFor(String code) {
    final clean = code.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    final h = Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode('activate|$clean')).bytes;
    return _group(_b32(h, 20), 5); // e.g. ABCDE-FGHJK-MNPQR-STVWX
  }

  static String _norm(String s) => s.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

  /// True if [key] matches this device's code.
  static Future<bool> keyValid(String key) async => _norm(keyFor(await deviceCode())) == _norm(key);

  /// Reads saved state and verifies it still matches this device.
  static Future<bool> load() async {
    final saved = await Repo.i.setting('license_key');
    activated = saved.isNotEmpty && await keyValid(saved);
    return activated;
  }

  /// Stores the key if it is correct for this device.
  static Future<bool> activate(String key) async {
    if (!await keyValid(key)) return false;
    await Repo.i.setSetting('license_key', _norm(key));
    activated = true;
    return true;
  }
}
