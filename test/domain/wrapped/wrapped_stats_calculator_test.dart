import 'package:cuacfm/domain/wrapped/wrapped_stats_calculator.dart';
import 'package:cuacfm/models/program.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> live({
  required int seconds,
  String date = '2026-01-01',
  int month = 1,
}) =>
    {
      'type': 'live',
      'programName': '',
      'durationSeconds': seconds,
      'date': date,
      'month': month,
      'year': 2026,
    };

Map<String, dynamic> podcast({
  required String program,
  required int seconds,
  String episodeId = '',
  String episodeTitle = '',
  String date = '2026-01-01',
  int month = 1,
}) =>
    {
      'type': 'podcast',
      'programName': program,
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
      'durationSeconds': seconds,
      'date': date,
      'month': month,
      'year': 2026,
    };

Map<String, dynamic> favorite(String program, {String action = 'add'}) => {
      'type': 'favorite',
      'action': action,
      'programName': program,
      'date': '2026-01-01',
      'month': 1,
      'year': 2026,
    };

Program program(String name, String category) =>
    Program.fromFavorite({'name': name, 'category': category});

void main() {
  final calc = WrappedStatsCalculator();

  test('empty sessions produce empty stats', () {
    final stats = calc.calculate([], year: 2026);
    expect(stats.hasData, isFalse);
    expect(stats.totalSeconds, 0);
    expect(stats.year, 2026);
  });

  test('sums live and podcast seconds separately', () {
    final stats = calc.calculate([
      live(seconds: 600),
      live(seconds: 300),
      podcast(program: 'A', seconds: 1200),
    ], year: 2026);
    expect(stats.liveSeconds, 900);
    expect(stats.podcastSeconds, 1200);
    expect(stats.totalSeconds, 2100);
    expect(stats.listeningSessions, 3);
    expect(stats.hasData, isTrue);
  });

  test('ignores sessions with non-positive duration', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 0),
      podcast(program: 'A', seconds: 500),
    ], year: 2026);
    expect(stats.listeningSessions, 1);
    expect(stats.podcastSeconds, 500);
  });

  test('ranks top 3 programs by total time', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 100),
      podcast(program: 'B', seconds: 500),
      podcast(program: 'C', seconds: 300),
      podcast(program: 'D', seconds: 50),
      podcast(program: 'B', seconds: 100),
    ], year: 2026);
    expect(stats.topPrograms.length, 3);
    expect(stats.topPrograms[0].name, 'B');
    expect(stats.topPrograms[0].seconds, 600);
    expect(stats.topPrograms[1].name, 'C');
    expect(stats.topPrograms[2].name, 'A');
  });

  test('picks most listened episode by episodeId', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 200, episodeId: 'e1', episodeTitle: 'Ep 1'),
      podcast(program: 'A', seconds: 300, episodeId: 'e1', episodeTitle: 'Ep 1'),
      podcast(program: 'A', seconds: 400, episodeId: 'e2', episodeTitle: 'Ep 2'),
    ], year: 2026);
    expect(stats.topEpisodeTitle, 'Ep 1');
    expect(stats.topEpisodeSeconds, 500);
  });

  test('resolves favorite category by crossing program name', () {
    final stats = calc.calculate([
      podcast(program: 'O Desinformativo', seconds: 1000),
      podcast(program: 'Recendo', seconds: 400),
    ], year: 2026, programs: [
      program('O Desinformativo', 'Novas'),
      program('Recendo', 'Música'),
    ]);
    expect(stats.favoriteCategory, 'Novas');
    expect(stats.favoriteCategorySeconds, 1000);
  });

  test('category matching is case and space insensitive', () {
    final stats = calc.calculate([
      podcast(program: '  o desinformativo ', seconds: 1000),
    ], year: 2026, programs: [
      program('O Desinformativo', 'Novas'),
    ]);
    expect(stats.favoriteCategory, 'Novas');
  });

  test('counts distinct discovered programs', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 100),
      podcast(program: 'A', seconds: 100),
      podcast(program: 'B', seconds: 100),
    ], year: 2026);
    expect(stats.programsDiscovered, 2);
  });

  test('counts only favorite add actions', () {
    final stats = calc.calculate([
      favorite('A'),
      favorite('B'),
      favorite('A', action: 'remove'),
    ], year: 2026);
    expect(stats.favoritesAdded, 2);
  });

  test('finds day and month with most listening', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 100, date: '2026-03-01', month: 3),
      podcast(program: 'A', seconds: 800, date: '2026-05-10', month: 5),
      podcast(program: 'A', seconds: 300, date: '2026-05-11', month: 5),
    ], year: 2026);
    expect(stats.topDate, '2026-05-10');
    expect(stats.topDateSeconds, 800);
    expect(stats.topMonth, 5);
    expect(stats.topMonthSeconds, 1100);
  });

  test('computes longest consecutive-day streak', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 100, date: '2026-02-01'),
      podcast(program: 'A', seconds: 100, date: '2026-02-02'),
      podcast(program: 'A', seconds: 100, date: '2026-02-03'),
      podcast(program: 'A', seconds: 100, date: '2026-02-05'),
      podcast(program: 'A', seconds: 100, date: '2026-02-06'),
    ], year: 2026);
    expect(stats.longestStreakDays, 3);
  });

  test('streak counts duplicated dates as one day', () {
    final stats = calc.calculate([
      podcast(program: 'A', seconds: 100, date: '2026-02-01'),
      podcast(program: 'A', seconds: 100, date: '2026-02-01'),
      podcast(program: 'A', seconds: 100, date: '2026-02-02'),
    ], year: 2026);
    expect(stats.longestStreakDays, 2);
  });
}
