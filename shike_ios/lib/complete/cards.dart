import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/rewards.dart' show RewardCard;
import '../src/store.dart';
import '../src/media.dart' show storedImage;
import 'controller.dart';
import '../refined/design.dart';
import '../refined/art_data.dart';
import '../refined/export.dart';

final Future<ui.Image> _covers = ui
    .instantiateImageCodec(base64Decode(cardArtBase64))
    .then((codec) async {
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });

Widget refinedPhoto(String path, {BoxFit fit = BoxFit.cover}) =>
    path.startsWith('refined-art:')
    ? KeepsakeArt(int.parse(path.split(':').last))
    : storedImage(path, fit: fit);

class KeepsakeArt extends StatelessWidget {
  final int panel;
  const KeepsakeArt(this.panel, {super.key});
  @override
  Widget build(BuildContext c) => FutureBuilder<ui.Image>(
    future: _covers,
    builder: (c, s) => s.hasData
        ? CustomPaint(
            painter: _ArtPainter(s.data!, panel),
            child: const SizedBox.expand(),
          )
        : const ColoredBox(color: Paper.soft),
  );
}

class _ArtPainter extends CustomPainter {
  final ui.Image image;
  final int panel;
  _ArtPainter(this.image, this.panel);
  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(image.width / 3, image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, source, size);
    final src = Alignment.center.inscribe(
      fitted.source,
      Offset(panel * source.width, 0) & source,
    );
    final dst = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.image != image || old.panel != panel;
}

int cardPanel(RewardCard card) =>
    card.title.contains('茶') || card.title.contains('水果')
    ? 1
    : card.title.contains('礼') ||
          card.title.contains('愿望') ||
          card.title.contains('全能')
    ? 2
    : 0;

class CardPoster extends StatelessWidget {
  final RewardCard card;
  final String? photo;
  final bool detail;
  const CardPoster({
    super.key,
    required this.card,
    this.photo,
    this.detail = false,
  });
  @override
  Widget build(BuildContext c) => DecoratedBox(
    decoration: BoxDecoration(
      color: Paper.bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFEDE6DA), width: .6),
      boxShadow: [
        BoxShadow(
          color: Paper.ink.withValues(alpha: .05),
          blurRadius: 9,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding: EdgeInsets.all(detail ? 16 : 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: photo == null
                  ? KeepsakeArt(cardPanel(card))
                  : SizedBox.expand(child: storedImage(photo!)),
            ),
          ),
          SizedBox(height: detail ? 20 : 14),
          Text(
            card.title,
            style: detail ? Paper.title(24) : Paper.title(16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail) ...[
            const SizedBox(height: 12),
            Text(card.description, style: Paper.meta.copyWith(height: 1.8)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(top: detail ? 16 : 6, bottom: 3),
              child: const LineMark(
                Mark.leaf,
                size: 21,
                color: Color(0xFFB6A68D),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RefinedCardPack extends StatelessWidget {
  final CompleteController controller;
  const RefinedCardPack({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('我的小刻痕'),
    body: AnimatedBuilder(
      animation: controller,
      builder: (c, _) {
        final cards = controller.cards.reversed.toList();
        return cards.isEmpty
            ? const EmptyNote('还没有小刻痕。慢慢来。')
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 18,
                  childAspectRatio: .66,
                ),
                itemCount: cards.length,
                itemBuilder: (c, i) {
                  final card = cards[i];
                  return Semantics(
                    button: true,
                    label: '查看${card.title}',
                    child: InkWell(
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute(
                          builder: (_) => RefinedCardDetail(
                            controller: controller,
                            card: card,
                          ),
                        ),
                      ),
                      child: CardPoster(
                        card: card,
                        photo: controller.cardImages[card.key],
                      ),
                    ),
                  );
                },
              );
      },
    ),
  );
}

class RefinedCardDetail extends StatefulWidget {
  final CompleteController controller;
  final RewardCard card;
  const RefinedCardDetail({
    super.key,
    required this.controller,
    required this.card,
  });
  @override
  State<RefinedCardDetail> createState() => _RefinedCardDetailState();
}

class _RefinedCardDetailState extends State<RefinedCardDetail> {
  final captureKey = GlobalKey();
  bool saving = false;
  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final saved = await savePng(
        await captureBoundary(captureKey),
        '拾刻-${widget.card.key}.png',
      );
      if (mounted && saved) tell(context, '已保存图片');
    } catch (_) {
      if (mounted) tell(context, '无法保存图片，请检查相册权限或文件位置。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('卡片详情'),
    body: LayoutBuilder(
      builder: (c, box) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          RepaintBoundary(
            key: captureKey,
            child: AspectRatio(
              aspectRatio: .63,
              child: CardPoster(
                card: widget.card,
                photo: widget.controller.cardImages[widget.card.key],
                detail: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: saving ? null : save,
              icon: const LineMark(Mark.download, size: 20),
              label: Text(saving ? '保存中' : '存到相册'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> completionFeedback(
  BuildContext context,
  CompleteController controller,
  Diary entry,
) async {
  if (!context.mounted) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  if (entry.state != 'capsule' && (entry.mood ?? 5) <= 2) {
    try {
      final phrase = await controller.phrase('low');
      if (phrase != null) {
        final e = OverlayEntry(
          builder: (_) => IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Paper.soft.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    phrase,
                    textAlign: TextAlign.center,
                    style: Paper.body.copyWith(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        );
        overlay.insert(e);
        Timer(const Duration(milliseconds: 2500), e.remove);
      }
    } catch (_) {
      /* Journal save has already succeeded. */
    }
  }
  try {
    final cards = await controller.reward(entry);
    if (cards.isEmpty) return;
    Timer(Duration(milliseconds: (entry.mood ?? 5) <= 2 ? 2700 : 0), () {
      if (context.mounted) showRewardBatch(context, controller, cards);
    });
  } catch (_) {
    /* Reward errors do not turn a saved journal into a failed submission. */
  }
}

void showRewardBatch(
  BuildContext context,
  CompleteController controller,
  List<RewardCard> cards,
) {
  if (cards.isEmpty || !context.mounted) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  unawaited(HapticFeedback.lightImpact().catchError((_) {}));
  late OverlayEntry item;
  bool removed = false;
  void remove() {
    if (!removed) {
      removed = true;
      item.remove();
    }
  }

  item = OverlayEntry(
    builder: (c) => Positioned(
      left: 24,
      right: 24,
      bottom: 100,
      child: Material(
        color: Paper.bg,
        borderRadius: BorderRadius.circular(9),
        elevation: 2,
        child: InkWell(
          onTap: () {
            remove();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RewardBatchPage(controller: controller, cards: cards),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const LineMark(Mark.card, size: 27),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    cards.length == 1
                        ? cards.first.title
                        : '拾起了 ${cards.length} 张小刻痕',
                    style: Paper.title(17),
                  ),
                ),
                const LineMark(Mark.next, size: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(item);
  Timer(const Duration(seconds: 6), remove);
}

class RewardBatchPage extends StatelessWidget {
  final CompleteController controller;
  final List<RewardCard> cards;
  const RewardBatchPage({
    super.key,
    required this.controller,
    required this.cards,
  });
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('这次的小刻痕'),
    body: GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: .62,
      ),
      itemCount: cards.length,
      itemBuilder: (c, i) => GestureDetector(
        onTap: () => Navigator.push(
          c,
          MaterialPageRoute(
            builder: (_) =>
                RefinedCardDetail(controller: controller, card: cards[i]),
          ),
        ),
        child: CardPoster(
          card: cards[i],
          photo: controller.cardImages[cards[i].key],
        ),
      ),
    ),
  );
}
