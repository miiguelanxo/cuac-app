class WrappedProgramTime {
  final String name;
  final int seconds;

  const WrappedProgramTime(this.name, this.seconds);
}

class WrappedStats {
  final int year;
  final int totalSeconds;
  final int liveSeconds;
  final int podcastSeconds;
  final int listeningSessions;
  final List<WrappedProgramTime> topPrograms;
  final String topEpisodeTitle;
  final int topEpisodeSeconds;
  final String favoriteCategory;
  final int favoriteCategorySeconds;
  final int programsDiscovered;
  final int favoritesAdded;
  final String topDate;
  final int topDateSeconds;
  final int topMonth;
  final int topMonthSeconds;
  final int longestStreakDays;

  const WrappedStats({
    required this.year,
    required this.totalSeconds,
    required this.liveSeconds,
    required this.podcastSeconds,
    required this.listeningSessions,
    required this.topPrograms,
    required this.topEpisodeTitle,
    required this.topEpisodeSeconds,
    required this.favoriteCategory,
    required this.favoriteCategorySeconds,
    required this.programsDiscovered,
    required this.favoritesAdded,
    required this.topDate,
    required this.topDateSeconds,
    required this.topMonth,
    required this.topMonthSeconds,
    required this.longestStreakDays,
  });

  factory WrappedStats.empty(int year) => WrappedStats(
        year: year,
        totalSeconds: 0,
        liveSeconds: 0,
        podcastSeconds: 0,
        listeningSessions: 0,
        topPrograms: const [],
        topEpisodeTitle: '',
        topEpisodeSeconds: 0,
        favoriteCategory: '',
        favoriteCategorySeconds: 0,
        programsDiscovered: 0,
        favoritesAdded: 0,
        topDate: '',
        topDateSeconds: 0,
        topMonth: 0,
        topMonthSeconds: 0,
        longestStreakDays: 0,
      );

  bool get hasData => totalSeconds > 0 || listeningSessions > 0;

  int get totalMinutes => (totalSeconds / 60).round();
  int get liveMinutes => (liveSeconds / 60).round();
  int get podcastMinutes => (podcastSeconds / 60).round();
}
