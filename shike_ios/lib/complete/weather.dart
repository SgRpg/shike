import 'package:flutter/services.dart';

import 'model.dart';

typedef WeatherRequest = Future<Json> Function(String method, Json args);

class WeatherService {
  static const channel = MethodChannel('shike/private');
  final WeatherRequest request;
  final DateTime Function() clock;
  final Map<String, Json> _cache = {};
  WeatherService({WeatherRequest? request, DateTime Function()? clock})
    : request =
          request ??
          ((method, args) async =>
              Json.from(await channel.invokeMapMethod(method, args) ?? {})),
      clock = clock ?? DateTime.now;
  Future<Json?> fetch(double latitude, double longitude) async {
    // Round before crossing the native/network boundary. Never send precise GPS.
    final lat = (latitude * 10).round() / 10,
        lng = (longitude * 10).round() / 10;
    final key = '$lat,$lng';
    final cached = _cache[key];
    if (cached != null &&
        clock().difference(DateTime.parse(cached['fetchedAt'])) <
            const Duration(minutes: 15)) {
      return cached;
    }
    try {
      final current = await request('weather', {
        'latitude': lat,
        'longitude': lng,
      }).timeout(const Duration(seconds: 3));
      final code = current['weather_code'] as int;
      final value = {
        'temperature': (current['temperature_2m'] as num).round(),
        'code': code,
        'label': code == 0
            ? '晴'
            : code <= 3
            ? '多云'
            : code <= 48
            ? '雾'
            : (code >= 71 && code <= 77) || (code >= 85 && code <= 86)
            ? '雪'
            : '雨',
        'fetchedAt': clock().toIso8601String(),
        'cityKey': key,
      };
      _cache[key] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<List<Json>> search(String name) async {
    final result = await request('searchCity', {
      'name': name.trim(),
    }).timeout(const Duration(seconds: 3));
    return [for (final j in result['results'] ?? []) Json.from(j)];
  }

  Future<Json> locate() async => request('locate', {});
}
