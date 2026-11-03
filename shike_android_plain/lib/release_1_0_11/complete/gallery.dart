import 'android_photo_import.dart';

import 'package:flutter/material.dart';

import 'controller.dart';
import '../refined/design.dart';
import 'cards.dart' show refinedPhoto, showRewardBatch;
import '../src/rewards.dart' show RewardCard;

class RefinedGallery extends StatefulWidget {
  final CompleteController controller;
  const RefinedGallery({super.key, required this.controller});
  @override
  State<RefinedGallery> createState() => _RefinedGalleryState();
}

class _RefinedGalleryState extends State<RefinedGallery> {
  bool importing = false;
  Future<void> import() async {
    if (importing) return;
    setState(() => importing = true);
    var count = 0;
    try {
      final files = await AndroidPhotoImport.pick(widget.controller);
      count = files.length;
    } catch (_) {
      if (mounted) {
        tell(
          context,
          count == 0 ? '无法导入照片，请检查相册权限。' : '已导入 $count 张，其余照片暂未导入。',
        );
      }
    } finally {
      if (mounted) {
        setState(() => importing = false);
        showRewardBatch(
          context,
          widget.controller,
          widget.controller.unpresented.map(RewardCard.fromJson).toList(),
        );
        widget.controller.unpresented.clear();
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: PaperHeader(
      '拾影',
      actions: [
        IconAction(Mark.plus, label: '导入照片', onTap: importing ? null : import),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (c, _) {
        final photos = widget.controller.photos;
        if (photos.isEmpty) return const EmptyNote('还没有照片。存一张想留住的吧。');
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .56,
          ),
          itemCount: photos.length,
          itemBuilder: (c, i) {
            final photo = photos[i];
            return Semantics(
              button: true,
              label: photo.description.isEmpty ? '查看照片' : photo.description,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                      builder: (_) => PhotoReading(
                        controller: widget.controller,
                        initialId: photo.id,
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      refinedPhoto(photo.path),
                      if (photo.description.isNotEmpty)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xB3000000)],
                              ),
                            ),
                            child: Text(
                              photo.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class PhotoReading extends StatefulWidget {
  final CompleteController controller;
  final String initialId;
  const PhotoReading({
    super.key,
    required this.controller,
    required this.initialId,
  });
  @override
  State<PhotoReading> createState() => _PhotoReadingState();
}

class _PhotoReadingState extends State<PhotoReading> {
  late final PageController pager;
  late String currentId;
  bool deleting = false;
  @override
  void initState() {
    super.initState();
    currentId = widget.initialId;
    final at = widget.controller.photos.indexWhere((p) => p.id == currentId);
    pager = PageController(initialPage: at < 0 ? 0 : at);
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  GalleryPhoto? get current =>
      widget.controller.photos.where((p) => p.id == currentId).firstOrNull;
  Future<void> edit() async {
    final photo = current;
    if (photo == null) return;
    final text = TextEditingController(text: photo.description);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('照片描述'),
        content: TextField(
          controller: text,
          minLines: 2,
          maxLines: 5,
          maxLength: 300,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, text.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null) return;
    photo.description = value;
    await widget.controller.savePhotos();
    if (mounted) setState(() {});
  }

  Future<void> remove() async {
    if (deleting) return;
    final photo = current;
    if (photo == null) return;
    if (!await confirm(context, '删除这张照片？删除后不可恢复。', yes: '删除', no: '取消')) return;
    setState(() => deleting = true);
    try {
      final index = widget.controller.photos.indexOf(photo);
      await widget.controller.removePhoto(photo.id);
      if (!mounted) return;
      if (widget.controller.photos.isEmpty) {
        Navigator.pop(context);
        return;
      }
      final next = index.clamp(0, widget.controller.photos.length - 1);
      currentId = widget.controller.photos[next].id;
      pager.jumpToPage(next);
    } catch (_) {
      if (mounted) tell(context, '暂时没能删除，请再试一次。');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: PaperHeader('拾影', actions: [IconAction(Mark.trash, label: '删除照片',
      color: const Color(0xFFB48A84), size: 20, onTap: deleting ? null : remove)]),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (c, _) => PageView.builder(
        controller: pager,
        itemCount: widget.controller.photos.length,
        onPageChanged: (i) =>
            setState(() => currentId = widget.controller.photos[i].id),
        itemBuilder: (c, i) {
          final photo = widget.controller.photos[i];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 32),
            children: [
              AspectRatio(
                aspectRatio: .78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: SizedBox.expand(child: refinedPhoto(photo.path)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Padding(padding: const EdgeInsets.only(left: 4, top: 9),
                  child: Text(photo.description, style: Paper.body))),
                IconAction(Mark.pen, label: '编辑描述', size: 17, color: Paper.faint, onTap: edit),
              ]),
            ],
          );
        },
      ),
    ),
  );
}
