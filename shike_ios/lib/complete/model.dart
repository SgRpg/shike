import 'dart:convert';

import '../src/store.dart';

typedef Json = Map<String, dynamic>;
Json cloneJson(Json value) => jsonDecode(jsonEncode(value)) as Json;
String naturalDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String mondayKey(DateTime d) =>
    naturalDay(DateTime(d.year, d.month, d.day - d.weekday + 1));
String? normalizedWeek(dynamic value) {
  if (value is! String) return null;
  final parts = value.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((v) => v == null)) return null;
  return naturalDay(DateTime(parts[0]!, parts[1]!, parts[2]!));
}

Json? usableWeather(Json settings, Json meta, DateTime now) {
  if (settings['weather'] != true || meta['currentWeather'] == null) {
    return null;
  }
  final value = Json.from(meta['currentWeather']);
  final fetched = DateTime.tryParse(value['fetchedAt'] as String? ?? '');
  final lat = settings['latitude'] as num?, lng = settings['longitude'] as num?;
  if (fetched == null || lat == null || lng == null) return null;
  final age = now.difference(fetched);
  final cityKey = '${(lat * 10).round() / 10},${(lng * 10).round() / 10}';
  return age.isNegative ||
          age >= const Duration(minutes: 15) ||
          value['cityKey'] != cityKey
      ? null
      : value;
}

/// Offsets are UTF-16 code units, matching Flutter's TextSelection.
class SentenceLink {
  final String id, source, target, quote;
  final int start, end;
  const SentenceLink({
    required this.id,
    required this.source,
    required this.target,
    required this.quote,
    required this.start,
    required this.end,
  });
  factory SentenceLink.fromJson(Json j) => SentenceLink(
    id: j['id'],
    source: j['source'],
    target: j['target'],
    quote: j['quote'],
    start: j['start'],
    end: j['end'],
  );
  Json toJson() => {
    'id': id,
    'source': source,
    'target': target,
    'quote': quote,
    'start': start,
    'end': end,
  };
  bool fits(String text) =>
      start >= 0 &&
      end > start &&
      end <= text.length &&
      _boundary(text, start) &&
      _boundary(text, end) &&
      text.substring(start, end) == quote;
  bool touches(int a, int b) => start < b && end > a;
  SentenceLink shifted(int offset) => SentenceLink(
    id: id,
    source: source,
    target: target,
    quote: quote,
    start: start + offset,
    end: end + offset,
  );
  SentenceLink remap(Map<String, String> ids) => SentenceLink(
    id: id,
    source: ids[source] ?? source,
    target: ids[target] ?? target,
    quote: quote,
    start: start,
    end: end,
  );
  static bool _boundary(String s, int i) =>
      i == 0 ||
      i == s.length ||
      !(s.codeUnitAt(i - 1) >= 0xd800 &&
          s.codeUnitAt(i - 1) <= 0xdbff &&
          s.codeUnitAt(i) >= 0xdc00 &&
          s.codeUnitAt(i) <= 0xdfff);
}

class LinkEditing {
  /// The minimal contiguous replacement. Edits inside a link invalidate it;
  /// insertions at its start shift it, and insertions at its end preserve it.
  static List<SentenceLink> rebase(
    String before,
    String after,
    List<SentenceLink> links, {
    int? selectionStart,
    int? selectionEnd,
  }) {
    if (before == after) return List.of(links);
    var a = 0;
    while (a < before.length &&
        a < after.length &&
        before.codeUnitAt(a) == after.codeUnitAt(a)) {
      a++;
    }
    var b = before.length, c = after.length;
    while (b > a &&
        c > a &&
        before.codeUnitAt(b - 1) == after.codeUnitAt(c - 1)) {
      b--;
      c--;
    }
    if (selectionStart != null && selectionEnd != null) {
      var start = selectionStart, end = selectionEnd;
      if (start == end && after.length < before.length) {
        start = (start + after.length - before.length).clamp(0, before.length);
      }
      final inserted = after.length - before.length + end - start;
      if (start >= 0 &&
          end >= start &&
          end <= before.length &&
          inserted >= 0 &&
          start + inserted <= after.length &&
          before.substring(0, start) == after.substring(0, start) &&
          before.substring(end) == after.substring(start + inserted)) {
        a = start;
        b = end;
        c = start + inserted;
      }
    }
    final delta = c - b;
    return [
      for (final r in links)
        if (r.end <= a)
          r
        else if (r.start >= b && !(a == b && r.start < a && r.end > a))
          r.shifted(delta),
    ].where((r) => r.fits(after)).toList();
  }

  static List<SentenceLink> replace(
    List<SentenceLink> links,
    SentenceLink added,
    String text,
  ) {
    if (!added.fits(text)) throw ArgumentError('引用选区无效');
    return [...links.where((r) => !r.touches(added.start, added.end)), added]
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  static void validate(String source, String text, List<SentenceLink> links) {
    final sorted = List<SentenceLink>.of(links)
      ..sort((a, b) => a.start.compareTo(b.start));
    final ids = <String>{};
    var end = 0;
    for (final r in sorted) {
      if (r.source != source ||
          !r.fits(text) ||
          r.start < end ||
          !ids.add(r.id)) {
        throw ArgumentError('引用位置或关系无效');
      }
      end = r.end;
    }
  }
}

class JournalVisibility {
  static bool readable(Diary d, Json capsule, DateTime now) =>
      d.state != 'draft' &&
      (d.state != 'capsule' ||
          capsule['releasedAt'] != null ||
          (d.unlockAt != null && !now.toUtc().isBefore(d.unlockAt!.toUtc())));
  static bool eligibleTarget(Diary d, Json capsule, DateTime now) =>
      readable(d, capsule, now);
  static bool validUnlock(DateTime created, DateTime unlock) =>
      !unlock.toUtc().isBefore(created.toUtc().add(const Duration(hours: 1))) &&
      !unlock.toUtc().isAfter(
        DateTime(
          created.year + 10,
          created.month,
          created.day,
          created.hour,
          created.minute,
          created.second,
          created.millisecond,
          created.microsecond,
        ).toUtc(),
      );
}

class BusinessEvent {
  final String id, kind;
  final DateTime at;
  final Json data;
  const BusinessEvent(this.id, this.kind, this.at, [this.data = const {}]);
  Json toJson() => {
    'id': id,
    'kind': kind,
    'at': at.toIso8601String(),
    'data': data,
  };
  factory BusinessEvent.fromJson(Json j) => BusinessEvent(
    j['id'],
    j['kind'],
    DateTime.parse(j['at']),
    Json.from(j['data']),
  );
}

/// Collections are persisted in one SQLite transaction. No partial journal save
/// can leave behind attachments, references, metadata or a lost reward event.
class JournalState {
  final Json entries,
      links,
      snapshots,
      drafts,
      media,
      events,
      grants,
      capsules,
      settings,
      meta,
      gallery,
      resources;
  JournalState({
    Json? entries,
    Json? links,
    Json? snapshots,
    Json? drafts,
    Json? media,
    Json? events,
    Json? grants,
    Json? capsules,
    Json? settings,
    Json? meta,
    Json? gallery,
    Json? resources,
  }) : entries = entries ?? {},
       links = links ?? {},
       snapshots = snapshots ?? {},
       drafts = drafts ?? {},
       media = media ?? {},
       events = events ?? {},
       grants = grants ?? {},
       capsules = capsules ?? {},
       settings = settings ?? {},
       meta = meta ?? {},
       gallery = gallery ?? {},
       resources = resources ?? {};
  factory JournalState.fromJson(Json j) => JournalState(
    entries: Json.from(j['entries'] ?? {}),
    links: Json.from(j['links'] ?? {}),
    snapshots: Json.from(j['snapshots'] ?? {}),
    drafts: Json.from(j['drafts'] ?? {}),
    media: Json.from(j['media'] ?? {}),
    events: Json.from(j['events'] ?? {}),
    grants: Json.from(j['grants'] ?? {}),
    capsules: Json.from(j['capsules'] ?? {}),
    settings: Json.from(j['settings'] ?? {}),
    meta: Json.from(j['meta'] ?? {}),
    gallery: Json.from(j['gallery'] ?? {}),
    resources: Json.from(j['resources'] ?? {}),
  );
  Json toJson() => {
    'entries': entries,
    'links': links,
    'snapshots': snapshots,
    'drafts': drafts,
    'media': media,
    'events': events,
    'grants': grants,
    'capsules': capsules,
    'settings': settings,
    'meta': meta,
    'gallery': gallery,
    'resources': resources,
  };
  JournalState copy() => JournalState.fromJson(cloneJson(toJson()));
}
