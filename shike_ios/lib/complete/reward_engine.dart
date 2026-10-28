import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:lunar/lunar.dart';

import '../src/store.dart';
import 'model.dart';
import 'persistence.dart';

class RewardProbabilities {
  final double remembered, contextual;
  const RewardProbabilities({this.remembered = 1 / 60, this.contextual = .2});
}

class RewardEngine {
  final AtomicState state;
  final double Function() lottery;
  final RewardProbabilities probabilities;
  RewardEngine(
    this.state, {
    double Function()? lottery,
    this.probabilities = const RewardProbabilities(),
  }) : lottery = lottery ?? Random.secure().nextDouble;

  Future<List<Json>> evaluate(BusinessEvent event) => state.transaction((s) {
    final stored = s.events[event.id];
    if (stored == null) throw StateError('事件必须先与业务数据一起保存');
    if (stored['processed'] == true) return <Json>[];
    final added = <Json>[];
    final attempts = Json.from(s.meta['rewardAttempts'] ?? {});
    void award(
      String key,
      String title,
      String description, {
      bool photo = false,
    }) {
      if (attempts.containsKey(key) || s.grants.containsKey(key)) return;
      attempts[key] = {'at': event.at.toIso8601String(), 'event': event.id};
      String? image;
      if (photo) {
        for (final resource in s.resources.entries) {
          if (resource.value['kind'] == 'photo' &&
              resource.value['used'] != true &&
              resource.value['available'] == true) {
            image = resource.key;
            resource.value['used'] = true;
            break;
          }
        }
        if (image == null) {
          attempts[key]['skipped'] = 'missing-photo';
          return;
        }
      }
      final card = <String, dynamic>{
        'key': key,
        'title': title,
        'description': description,
        'event': event.id,
        'at': event.at.toIso8601String(),
        'resource': ?image,
      };
      s.grants[key] = card;
      added.add(card);
    }

    void draw(
      String rule,
      String title,
      String description, {
      bool photo = false,
    }) {
      final key = '$rule:${naturalDay(event.at)}';
      if (attempts.containsKey(key) || s.grants.containsKey(key)) return;
      // The attempt is recorded whether the draw succeeds or not.
      if (lottery() < probabilities.contextual) {
        award(key, title, description, photo: photo);
      } else {
        attempts[key] = {'event': event.id, 'skipped': 'lottery'};
      }
    }

    if (event.kind == 'completed') {
      final d = Diary.fromJson(Json.from(s.entries[event.data['journal']]));
      if (d.state != 'capsule') {
        final ordinary = s.entries.values
            .map((j) => Diary.fromJson(Json.from(j)))
            .where((e) => e.state != 'draft' && e.state != 'capsule')
            .toList();
        final days = ordinary.map((e) => naturalDay(e.created)).toSet();
        for (final milestone in [
          (7, '照片卡', '这一段日子，留下一张照片。', true),
          (10, '点歌卡', '点一首喜欢的歌。', false),
          (14, '奶茶卡', '一杯奶茶。', false),
          (30, '礼物卡', '一个礼物。', false),
          (100, '大礼物卡', '一份大礼物。', false),
        ]) {
          if (days.length >= milestone.$1) {
            award(
              'total-${milestone.$1}',
              milestone.$2,
              milestone.$3,
              photo: milestone.$4,
            );
          }
        }
        var streak = 0;
        var day = DateTime(d.created.year, d.created.month, d.created.day);
        while (days.contains(naturalDay(day))) {
          streak++;
          day = DateTime(day.year, day.month, day.day - 1);
        }
        for (final milestone in [
          (3, '照片卡', '把这些日子轻轻留下。', true),
          (7, '零食卡', '一包喜欢的零食。', false),
          (14, '连续礼物卡', '一个礼物。', false),
          (30, '愿望卡', '一个不过分的小愿望。', false),
        ]) {
          if (streak >= milestone.$1) {
            award(
              'streak-${milestone.$1}',
              milestone.$2,
              milestone.$3,
              photo: milestone.$4,
            );
          }
        }
        final length = d.text.characters.length;
        if (length >= 500 && length < 1000) award('length-500', '长文卡', '晚饭一次。');
        if (length >= 1000) award('length-1000', '超长文卡', '一份小礼物。');
        if (d.photos.isNotEmpty) award('first-photo', '初次拾影卡', '第一次把照片写进日记。');
        if (d.audio != null) award('first-audio', '声音卡', '联系我，用约定的声音回应你。');
        if (d.text.isNotEmpty && d.photos.isNotEmpty && d.audio != null) {
          award('all-media', '全能卡', '一次小惊喜。');
        }
        final month = ordinary
            .where(
              (e) =>
                  e.created.year == event.at.year &&
                  e.created.month == event.at.month,
            )
            .toList();
        if (month.isNotEmpty &&
            month.where((e) => (e.mood ?? 0) >= 3).length / month.length > .6) {
          award(
            'happy:${event.at.year}-${event.at.month}',
            '水果卡',
            '这个月的甜，换一份水果。',
          );
        }
        final date = event.at;
        if (date.month == 6 && date.day == 30) {
          award('june30:${date.year}', '照片卡', '六月的最后一天。', photo: true);
        }
        final lunar = Solar.fromDate(date).getLunar();
        if (lunar.getMonth() == 8 && lunar.getDay() == 18) {
          award('birthday:${lunar.getYear()}', '生日蛋糕卡', '生日快乐呀小宝');
        }
        if (lunar.getMonth() == 10 && lunar.getDay() == 24) {
          award('reminder:${lunar.getYear()}', '小小提醒', '记得祝茁茁生日快乐');
        }
        if (date.hour < 3) draw('night', '夜猫卡', '夜深了，也记得照顾自己。');
        if (date.hour >= 5 && date.hour < 7) draw('morning', '早起卡', '把清晨留给你。');
        final weather = s.meta['weatherCodes']?[d.id] as int?;
        if (weather != null &&
            ((weather >= 51 && weather <= 67) ||
                (weather >= 80 && weather <= 82) ||
                weather >= 95)) {
          draw('rain', '雨天卡', '雨声里的一点温柔。');
        }
        if (weather != null &&
            ((weather >= 71 && weather <= 77) ||
                (weather >= 85 && weather <= 86))) {
          draw('snow', '雪天卡', '收下一片雪。');
        }
        if ((date.month == 1 && date.day == 1) ||
            (date.month == 2 && date.day == 14) ||
            (lunar.getMonth() == 7 && lunar.getDay() == 7) ||
            (lunar.getMonth() == 12 &&
                Solar.fromDate(DateTime(date.year, date.month, date.day + 1))
                        .getLunar()
                        .getMonth() ==
                    1)) {
          draw('holiday', '节日卡', '今天也有人惦记你。');
        }
        final randomKey = 'remembered:${naturalDay(date)}',
            week = mondayKey(date);
        if (!attempts.containsKey(randomKey)) {
          attempts[randomKey] = {'event': event.id};
          if (s.meta['randomWeek'] != week &&
              lottery() < probabilities.remembered) {
            // award() owns the attempt record for successful draws.
            attempts.remove(randomKey);
            award(randomKey, '被记住卡', '这一刻被轻轻记住了。');
            s.meta['randomWeek'] = week;
          }
        }
      }
    } else if (event.kind == 'gallery-imported') {
      final count =
          event.data['count'] as int? ??
          s.events[event.id]['data']['count'] as int;
      if (count > 0 && count % 30 == 0) {
        award('gallery:$count', '照片卡', '又拾起了三十个瞬间。', photo: true);
      }
    } else if (event.kind == 'capsule-opened') {
      final count = event.data['count'] as int;
      if ((count - 1) % 3 == 0) {
        award('capsule:$count', '开信礼物卡', '一封来自过去的信，一份现在的小礼物。');
      }
    }
    s.meta['rewardAttempts'] = attempts;
    stored['processed'] = true;
    stored['grants'] = added.map((e) => e['key']).toList();
    return added;
  });

  Future<List<Json>> processPending() async {
    final added = <Json>[];
    for (final event in state.snapshot.events.values) {
      if (event['processed'] != true) {
        added.addAll(await evaluate(BusinessEvent.fromJson(Json.from(event))));
      }
    }
    return added;
  }
}
