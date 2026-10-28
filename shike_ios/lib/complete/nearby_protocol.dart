import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'model.dart';

class NearbyPairing {
  final String session, host, key;
  final int port;
  final DateTime expires;
  NearbyPairing(this.session, this.host, this.port, this.key, this.expires);
  factory NearbyPairing.parse(String raw, DateTime now) {
    final j = Json.from(jsonDecode(raw));
    final expiry = DateTime.parse(j['expires']);
    final key = base64Decode(j['key']);
    final host = j['host'] as String;
    final address = host.split('.').map(int.tryParse).toList();
    final private =
        address.length == 4 &&
        address.every((n) => n != null && n >= 0 && n <= 255) &&
        (address[0] == 10 ||
            (address[0] == 172 && address[1]! >= 16 && address[1]! <= 31) ||
            (address[0] == 192 && address[1] == 168));
    if (j['version'] != 1 ||
        key.length != 32 ||
        !private ||
        j['port'] is! int ||
        j['port'] < 1 ||
        j['port'] > 65535 ||
        !expiry.isAfter(now) ||
        expiry.difference(now) > const Duration(minutes: 10) ||
        j['session'] is! String ||
        j['session'].length > 64) {
      throw const FormatException('配对信息无效或已过期');
    }
    return NearbyPairing(j['session'], host, j['port'], j['key'], expiry);
  }
  String encode() => jsonEncode({
    'version': 1,
    'session': session,
    'host': host,
    'port': port,
    'key': key,
    'expires': expires.toIso8601String(),
  });
  static String secureKey() =>
      base64Encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
}

class NearbyFrame {
  static const maxSize = 512 * 1024 * 1024;
  static Uint8List encode(Uint8List payload) {
    if (payload.length > maxSize) throw const FormatException('传输包过大');
    final bytes = Uint8List(16 + payload.length);
    bytes.setRange(0, 4, ascii.encode('SHK2'));
    final header = ByteData.sublistView(bytes);
    header.setUint64(4, payload.length);
    header.setUint32(12, getCrc32(payload));
    bytes.setRange(16, bytes.length, payload);
    return bytes;
  }

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List? _header;
  int _expected = 0;
  Uint8List? add(Uint8List data, {bool end = false}) {
    _buffer.add(data);
    if (_header == null && _buffer.length >= 16) {
      final all = _buffer.takeBytes();
      _header = Uint8List.sublistView(all, 0, 16);
      if (ascii.decode(_header!.sublist(0, 4)) != 'SHK2') {
        throw const FormatException('传输协议不符');
      }
      _expected = ByteData.sublistView(_header!).getUint64(4);
      if (_expected > maxSize) throw const FormatException('传输包过大');
      _buffer.add(Uint8List.sublistView(all, 16));
    }
    if (_header != null && _buffer.length > _expected) {
      throw const FormatException('传输长度不符');
    }
    if (_header != null && _buffer.length == _expected) {
      final result = _buffer.takeBytes();
      if (getCrc32(result) != ByteData.sublistView(_header!).getUint32(12)) {
        throw const FormatException('传输内容损坏');
      }
      return result;
    }
    if (end) throw const FormatException('传输中断，请重新发送');
    return null;
  }
}
