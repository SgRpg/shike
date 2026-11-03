import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../refined/design.dart';

class AndroidPermissions extends StatefulWidget {
  const AndroidPermissions({super.key});
  @override
  State<AndroidPermissions> createState() => _AndroidPermissionsState();
}

class _AndroidPermissionsState extends State<AndroidPermissions>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('shike/private');
  Map<String, dynamic> values = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await channel.invokeMapMethod<String, dynamic>(
        'permissionStatus',
      );
      if (mounted) setState(() => values = value ?? {});
    } catch (_) {
      /* The visual preview has no Android channel. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in values.entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(entry.key),
          trailing: Text(
            entry.value == true ? '已允许' : '未开启',
            style: Paper.meta,
          ),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('在系统设置中调整权限'),
        trailing: const LineMark(Mark.next, size: 17),
        onTap: () async {
          await channel.invokeMethod<void>('openSettings');
        },
      ),
    ],
  );
}
