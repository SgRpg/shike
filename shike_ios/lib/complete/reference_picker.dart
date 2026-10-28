import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../src/store.dart';
import '../refined/design.dart';
import 'controller.dart';
import 'reading.dart';

Future<Diary?> chooseReference(
  BuildContext context,
  CompleteController controller,
  String source,
) => showModalBottomSheet<Diary>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Paper.bg,
  showDragHandle: true,
  builder: (_) => ReferencePicker(controller: controller, source: source),
);

class ReferencePicker extends StatefulWidget {
  final CompleteController controller;
  final String source;
  const ReferencePicker({
    super.key,
    required this.controller,
    required this.source,
  });
  @override
  State<ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends State<ReferencePicker> {
  final query = TextEditingController(), scroll = ScrollController();
  @override
  void dispose() {
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  void select(Diary d) => Navigator.pop(context, d);
  Future<void> preview(Diary d) async {
    final chosen = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => ReadingPage(
          controller: widget.controller,
          entry: d,
          returnLabel: '返回列表',
          selectReference: true,
        ),
      ),
    );
    if (chosen == true && mounted) select(d);
  }

  @override
  Widget build(BuildContext context) {
    final search = query.text.trim().toLowerCase();
    final entries = widget.controller.visible
        .where(
          (d) =>
              d.id != widget.source &&
              (d.text.toLowerCase().contains(search) ||
                  '${d.created.year}.${d.created.month}.${d.created.day}'
                      .contains(search)),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .52,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                child: TextField(
                  controller: query,
                  decoration: const InputDecoration(
                    hintText: '搜索日记',
                    prefixIcon: Icon(Icons.search, size: 19),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyNote('还没有可以引用的日记。')
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, i) => const Divider(),
                        itemBuilder: (c, i) {
                          final d = entries[i];
                          return Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => preview(d),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${d.created.year}.${d.created.month}.${d.created.day}',
                                          style: Paper.meta,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          d.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Paper.body,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => select(d),
                                child: const Text('引用'),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
