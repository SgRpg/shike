import 'package:flutter/material.dart';

import '../refined/design.dart';

class BreathingQuickEntry extends StatefulWidget {

  final TextEditingController controller;

  final bool busy;

  final ValueChanged<String> onChanged;

  final InputDecoration decoration;

  const BreathingQuickEntry({super.key, required this.controller, required this.busy, required this.onChanged, required this.decoration});

  @override

  State<BreathingQuickEntry> createState() => _BreathingQuickEntryState();

}

class _BreathingQuickEntryState extends State<BreathingQuickEntry> with SingleTickerProviderStateMixin {

  final focus = FocusNode();

  late final breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  late final opacity = Tween<double>(begin: .3, end: .85).animate(CurvedAnimation(parent: breath, curve: Curves.easeInOut));

  late final thickness = Tween<double>(begin: 1.2, end: 3.2).animate(CurvedAnimation(parent: breath, curve: Curves.easeInOut));
  bool get showHint => !focus.hasFocus && widget.controller.text.isEmpty && !widget.busy;

  @override

  void initState() { super.initState(); focus.addListener(refresh); widget.controller.addListener(refresh); }

  void refresh() { if (mounted) setState(() {}); }

  @override

  void didChangeDependencies() { super.didChangeDependencies(); }

  @override

  void didUpdateWidget(BreathingQuickEntry old) {

    super.didUpdateWidget(old);

    if (old.controller != widget.controller) { old.controller.removeListener(refresh); widget.controller.addListener(refresh); }

  }

  @override

  void dispose() { widget.controller.removeListener(refresh); focus.removeListener(refresh); focus.dispose(); breath.dispose(); super.dispose(); }

  @override

  Widget build(BuildContext context) {

    final reduced = MediaQuery.disableAnimationsOf(context);

    if (showHint && !reduced && TickerMode.of(context)) {

      if (!breath.isAnimating) breath.repeat(reverse: true);

    } else { breath.stop(); }

    final fontSize = Paper.body.fontSize ?? 17;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final fontScale = scaledFontSize / fontSize;
    final cursorHeight = 19 * fontScale;
    final cursorWidth = 2 * fontScale;
    final cursorTop = 12 + (scaledFontSize * (Paper.body.height ?? 1) - cursorHeight) / 2;
    final cursor = AnimatedBuilder(
      animation: thickness,
      builder: (context, _) => Container(
        width: (reduced ? 2 : thickness.value) * fontScale,
        height: cursorHeight,
        color: Paper.faint,
      ),
    );

    return Stack(children: [

      TextField(

        key: const ValueKey('quick-text'), focusNode: focus, controller: widget.controller,

        minLines: 1, maxLines: 2, enabled: !widget.busy, onChanged: widget.onChanged,

        cursorWidth: cursorWidth, cursorHeight: cursorHeight, cursorColor: Paper.faint, style: Paper.body,

        decoration: widget.decoration.copyWith(contentPadding: EdgeInsets.fromLTRB(8 * fontScale, 12, 0, 12)),

      ),

      if (showHint) Positioned(left: 0, top: cursorTop, child: IgnorePointer(child: ExcludeSemantics(child: reduced ? Opacity(opacity: .45, child: cursor) : FadeTransition(opacity: opacity, child: cursor)))),

    ]);

  }

}

