import 'package:flutter/services.dart';
import 'controller.dart';

const _private = MethodChannel('shike/private');
bool _refreshing = false;

Future<void> prepareAutomaticSettings(CompleteController controller) async {
  await controller.repository.state.transaction((s) {
    if (s.meta['automaticEnvironmentVersion'] != 1) {
      // Old manually entered coordinates must not masquerade as a fresh location.
      s.settings.remove('city'); s.settings.remove('latitude'); s.settings.remove('longitude');
      s.meta.remove('currentWeather');
      s.meta['automaticEnvironmentVersion'] = 1;
    }
    s.settings.addAll({'greeting': true, 'location': true, 'weather': true});
  });
  controller.reload();
}

Future<void> requestStartupPermissions(CompleteController controller) async {
  if (controller.demo) return;
  final first = controller.repository.snapshot.meta['startupPermissionsV1'] != true;
  // Persist before showing a system sheet so denial or process death won't loop.
  if (first) await controller.repository.state.transaction((s) => s.meta['startupPermissionsV1'] = true);
  await refreshAutomaticEnvironment(controller, mayRequest: first);
  if (first) await controller.reconcileNotifications(requestPermission: true);
}

Future<void> refreshAutomaticEnvironment(CompleteController controller, {bool mayRequest = false}) async {
  if (controller.demo || _refreshing) return;
  _refreshing = true;
  try {
    final status = await _private.invokeMapMethod<String, dynamic>('permissionStatus');
    if (status?['定位'] != true && !mayRequest) return;
    final city = await controller.weather.locate();
    final name = city['city'] as String? ?? '';
    await controller.repository.state.transaction((s) {
      s.settings['city'] = name;
      s.settings['latitude'] = city['latitude'];
      s.settings['longitude'] = city['longitude'];
    });
    controller.reload();
    await controller.refreshWeather();
  } catch (_) {
    // No manual city substitution and no interruption to writing.
  } finally { _refreshing = false; }
}
