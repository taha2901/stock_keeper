// ignore_for_file: avoid_print
// Owner-only tool: turns a device code into an activation key.
//
//   dart run tool/keygen.dart ABCD-EFGH-JKMN
//
// Keep _secret identical to lib/services/license_service.dart, and private.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const _secret = 'SK-IZSJFK-OIFXBZ-K1JE08-NDE15X-WZU47N';
const _base32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String _b32(List<int> bytes, int chars) {
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

String _group(String s, int size) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && i % size == 0) b.write('-');
    b.write(s[i]);
  }
  return b.toString();
}

void main(List<String> args) {
  if (args.isEmpty) {
    print('الاستخدام: dart run tool/keygen.dart <كود الجهاز>');
    return;
  }
  final clean = args.join().toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
  final h = Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode('activate|$clean')).bytes;
  print('كود الجهاز : ${args.join(' ')}');
  print('مفتاح التفعيل : ${_group(_b32(h, 20), 5)}');
}
