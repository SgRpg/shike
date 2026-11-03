import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shike/complete/nearby_protocol.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30);
  Map<String, dynamic> valid() => {
    'version': 2,
    'session': 'session',
    'host': '192.168.1.5',
    'port': 32811,
    'key': NearbyPairing.secureKey(),
    'certificate': base64Encode(List.generate(400, (i) => i % 256)),
    'expires': now.add(const Duration(minutes: 10)).toIso8601String(),
  };
  test(
    'Android pairing retains the exact certificate pin across UI handoff',
    () {
      final raw = valid();
      final parsed = NearbyPairing.parse(jsonEncode(raw), now);
      expect(jsonDecode(parsed.encode()), raw);
    },
  );
  test('old iPhone pairing is explicitly rejected rather than silently using a different transport', () {
    final raw = valid()..['version'] = 1;
    expect(
      () => NearbyPairing.parse(jsonEncode(raw), now),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('备份文件'),
        ),
      ),
    );
  });
  test(
    'expired, public-network and unpinned pairing cannot start a transfer',
    () {
      for (final update in [
        {'host': '8.8.8.8'},
        {'host': '127.0.0.1'},
        {'port': 0},
        {'certificate': ''},
        {
          'key': base64Encode([1, 2]),
        },
        {'expires': now.toIso8601String()},
      ]) {
        expect(
          () => NearbyPairing.parse(jsonEncode({...valid(), ...update}), now),
          throwsFormatException,
        );
      }
    },
  );
}
