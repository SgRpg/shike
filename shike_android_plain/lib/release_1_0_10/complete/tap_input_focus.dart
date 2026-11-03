import 'package:flutter/material.dart';

final inputRouteObserver = RouteObserver<ModalRoute<dynamic>>();

class _InputLifecycle extends WidgetsBindingObserver {
  final ValueChanged<AppLifecycleState> onState;
  _InputLifecycle(this.onState);
  @override void didChangeAppLifecycleState(AppLifecycleState state) => onState(state);
}

/// Drop the route's remembered text focus before it can be restored on return.
/// Re-enable focusability without requesting focus; ordinary taps and accessible
/// text-field actions still use Flutter's own selection and keyboard handling.
mixin TapInputFocusPolicy<T extends StatefulWidget> on State<T> implements RouteAware {
  final inputFocus = FocusNode(debugLabel: 'explicit-input', canRequestFocus: false);
  ModalRoute<dynamic>? _watchedRoute;
  late final _InputLifecycle _lifecycle;
  bool _focusAllowed = false;
  bool _applicationActive = true;
  int _focusEpoch = 0;
  bool get allowInputFocus => _focusAllowed && _applicationActive;

  @override void initState() {
    super.initState();
    inputFocus.addListener(_focusChanged);
    _lifecycle = _InputLifecycle((state) {
      _applicationActive = state == AppLifecycleState.resumed;
      releaseInput(suspend: !_applicationActive);
    });
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  void _focusChanged() { if (mounted) setState(() {}); }

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _watchedRoute) {
      inputRouteObserver.unsubscribe(this);
      _watchedRoute = route;
      if (route != null) inputRouteObserver.subscribe(this, route);
    }
  }

  void releaseInput({bool suspend = false}) {
    final epoch = ++_focusEpoch;
    _focusAllowed = false;
    inputFocus.unfocus(disposition: UnfocusDisposition.scope);
    inputFocus.canRequestFocus = false;
    if (mounted) setState(() {});
    if (suspend || !_applicationActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _focusEpoch || !_applicationActive ||
          ModalRoute.of(context)?.isCurrent == false) return;
      // This grants eligibility only. Never call requestFocus/requestKeyboard.
      setState(() => _focusAllowed = true);
      inputFocus.canRequestFocus = true;
    });
  }

  @override void didPush() => releaseInput();
  @override void didPushNext() => releaseInput(suspend: true);
  @override void didPopNext() => releaseInput();
  @override void didPop() => releaseInput(suspend: true);

  @override void dispose() {
    _focusEpoch++;
    inputRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(_lifecycle);
    inputFocus.removeListener(_focusChanged);
    inputFocus.dispose();
    super.dispose();
  }
}
