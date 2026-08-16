import 'package:cuacfm/models/program.dart';
import 'package:cuacfm/models/wrapped_stats.dart';

class WrappedStatsCalculator {
  WrappedStats calculate(
    List<Map<String, dynamic>> sessions, {
    required int year,
    List<Program> programs = const [],
  }) {
    if (sessions.isEmpty) return WrappedStats.empty(year);

    final categoryByProgram = <String, String>{};
    for (final p in programs) {
      final key = _norm(p.name);
      if (key.isNotEmpty && p.category.isNotEmpty) {
        categoryByProgram[key] = p.category;
      }
    }

    var liveSeconds = 0;
    var podcastSeconds = 0;
    var listeningSessions = 0;
    var favoritesAdded = 0;
    final programSeconds = <String, int>{};
    final episodeSeconds = <String, int>{};
    final episodeTitles = <String, String>{};
    final categorySeconds = <String, int>{};
    final dateSeconds = <String, int>{};
    final monthSeconds = <int, int>{};
    final discovered = <String>{};
    final listeningDates = <String>{};

    for (final s in sessions) {
      final type = s['type'] as String? ?? '';
      if (type == 'favorite') {
        if ((s['action'] as String? ?? '') == 'add') favoritesAdded++;
        continue;
      }

      final seconds = (s['durationSeconds'] as num?)?.toInt() ?? 0;
      if (seconds <= 0) continue;
      listeningSessions++;

      final date = s['date'] as String? ?? '';
      if (date.isNotEmpty) {
        dateSeconds[date] = (dateSeconds[date] ?? 0) + seconds;
        listeningDates.add(date);
      }
      final month = (s['month'] as num?)?.toInt() ?? 0;
      if (month >= 1 && month <= 12) {
        monthSeconds[month] = (monthSeconds[month] ?? 0) + seconds;
      }

      if (type == 'live') {
        liveSeconds += seconds;
        continue;
      }

      podcastSeconds += seconds;
      final program = s['programName'] as String? ?? '';
      if (program.isNotEmpty) {
        programSeconds[program] = (programSeconds[program] ?? 0) + seconds;
        discovered.add(program);
        final category = categoryByProgram[_norm(program)];
        if (category != null) {
          categorySeconds[category] =
              (categorySeconds[category] ?? 0) + seconds;
        }
      }
      final episodeId = s['episodeId'] as String? ?? '';
      final episodeTitle = s['episodeTitle'] as String? ?? '';
      final episodeKey = episodeId.isNotEmpty ? episodeId : episodeTitle;
      if (episodeKey.isNotEmpty) {
        episodeSeconds[episodeKey] =
            (episodeSeconds[episodeKey] ?? 0) + seconds;
        if (episodeTitle.isNotEmpty) episodeTitles[episodeKey] = episodeTitle;
      }
    }

    final topPrograms = _topEntries(programSeconds, 3)
        .map((e) => WrappedProgramTime(e.key, e.value))
        .toList();

    final topEpisode = _topEntry(episodeSeconds);
    final topCategory = _topEntry(categorySeconds);
    final topDate = _topEntry(dateSeconds);
    final topMonth = _topEntryInt(monthSeconds);

    return WrappedStats(
      year: year,
      totalSeconds: liveSeconds + podcastSeconds,
      liveSeconds: liveSeconds,
      podcastSeconds: podcastSeconds,
      listeningSessions: listeningSessions,
      topPrograms: topPrograms,
      topEpisodeTitle:
          topEpisode == null ? '' : (episodeTitles[topEpisode.key] ?? ''),
      topEpisodeSeconds: topEpisode?.value ?? 0,
      favoriteCategory: topCategory?.key ?? '',
      favoriteCategorySeconds: topCategory?.value ?? 0,
      programsDiscovered: discovered.length,
      favoritesAdded: favoritesAdded,
      topDate: topDate?.key ?? '',
      topDateSeconds: topDate?.value ?? 0,
      topMonth: topMonth?.key ?? 0,
      topMonthSeconds: topMonth?.value ?? 0,
      longestStreakDays: _longestStreak(listeningDates),
    );
  }

  List<MapEntry<String, int>> _topEntries(Map<String, int> map, int limit) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  MapEntry<String, int>? _topEntry(Map<String, int> map) {
    final entries = _topEntries(map, 1);
    return entries.isEmpty ? null : entries.first;
  }

  MapEntry<int, int>? _topEntryInt(Map<int, int> map) {
    if (map.isEmpty) return null;
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first;
  }

  int _longestStreak(Set<String> dates) {
    if (dates.isEmpty) return 0;
    final days = dates
        .map((d) => DateTime.tryParse(d))
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList()
      ..sort();
    var longest = 1;
    var current = 1;
    for (var i = 1; i < days.length; i++) {
      final diff = days[i].difference(days[i - 1]).inDays;
      if (diff == 0) continue;
      if (diff == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }

  String _norm(String s) => s.toLowerCase().trim();
}
