import '../src/store.dart';
import '../src/rewards.dart' show RewardCard;
import 'controller.dart';

RefinedController visualFixture({DateTime? today}) {
  final now = today ?? DateTime.now();
  final store = PreviewStore();
  for (var i = 0; i < 9; i++) {
    final date = DateTime(now.year, now.month, now.day - i, 14 + i % 5, 20);
    store.entries.add(
      Diary(
        id: 'fixture-$i',
        text: i == 0
            ? '午后晒到一点太阳。'
            : i == 1
            ? '回家的路上，风很舒服。'
            : '给这一天留下一小段记录。',
        mood: [4, 2, 3, 5, 2, 4, 1, 3, 4][i],
        created: date,
        updated: date,
        state: 'done',
      ),
    );
  }
  final evening = DateTime(now.year, now.month, now.day, 20, 10);
  store.entries.add(
    Diary(
      id: 'fixture-evening',
      text: '傍晚的风很舒服。',
      mood: 4,
      created: evening,
      updated: evening,
      state: 'done',
    ),
  );
  final sealed = DateTime(now.year, now.month, now.day - 1, 18);
  store.entries.add(
    Diary(
      id: 'fixture-capsule',
      text: '这段内容只用于封存状态的测试，不应在封存时显示。',
      mood: 3,
      created: sealed,
      updated: sealed,
      state: 'capsule',
      unlockAt: now.add(const Duration(days: 3)),
    ),
  );
  final controller = RefinedController(store, demo: true);
  controller.cards.addAll([
    RewardCard('fixture-sky', '傍晚的云', '今天也辛苦了。'),
    RewardCard('fixture-tea', '一杯热茶', '给自己留一点柔软的时间。'),
    RewardCard('fixture-gift', '小小的礼物', '一份被记住的小惊喜。'),
  ]);
  // All these records remain in this isolated in-memory demo controller.
  for (var i = 0; i < 6; i++) {
    controller.photos.add(
      GalleryPhoto(
        id: 'demo-photo-$i',
        path: 'refined-art:${i % 3}',
        imported: DateTime(now.year, now.month, now.day - i),
        description: ['傍晚的云', '一杯热茶', '小小的礼物', '窗边的光', '安静的午后', '留住这一天'][i],
      ),
    );
  }
  return controller;
}
