import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:cuacfm/domain/invoker/invoker.dart';
import 'package:cuacfm/domain/repository/radiocom_repository_contract.dart';
import 'package:cuacfm/domain/result/result.dart';
import 'package:cuacfm/domain/usecase/get_favorites_use_case.dart';
import 'package:cuacfm/domain/usecase/get_playlist_use_case.dart';
import 'package:cuacfm/models/episode.dart';
import 'package:cuacfm/models/now.dart';
import 'package:cuacfm/models/program.dart';
import 'package:cuacfm/models/time_table.dart';
import 'package:cuacfm/ui/player/current_player.dart';
import 'package:injector/injector.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

class CuacAudioHandler extends BaseAudioHandler {
  static const _seekStep = Duration(seconds: 30);
  static const _tabLive = 'tab_live';
  static const _tabRecent = 'tab_recent';
  static const _tabFavorites = 'tab_favorites';
  static const _tabPlaylist = 'tab_playlist';
  static const _fallbackArt =
      'https://cuacfm.org/wp-content/uploads/2026/04/cuac_music_cover.png';

  static const _rewindControl = MediaControl(
    androidIcon: 'drawable/ic_replay_30',
    label: 'Retroceder 30 segundos',
    action: MediaAction.rewind,
  );
  static const _fastForwardControl = MediaControl(
    androidIcon: 'drawable/ic_forward_30',
    label: 'Avanzar 30 segundos',
    action: MediaAction.fastForward,
  );
  final AudioPlayer _player;
  bool _isLive = false;

  final Map<String, List<Episode>> _episodesByRss = {};
  final Map<String, TimeTable> _recentByKey = {};
  final Map<String, Program> _favoriteByRss = {};
  List<Map<String, dynamic>> _playlistItems = [];
  List<Program> _allProgramsCache = [];
  Now? _liveNow;

  CuacRepositoryContract get _repository =>
      Injector.appInstance.get<CuacRepositoryContract>();

  Invoker get _invoker => Injector.appInstance.get<Invoker>();

  CuacAudioHandler(this._player) {
    _player.playbackEventStream.listen((_) => _broadcastState());
    _player.playingStream.listen((_) => _broadcastState());
    _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (!_isLive && item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  void setNowPlaying(MediaItem item, {required bool isLive}) {
    _isLive = isLive;
    mediaItem.add(isLive ? item : item.copyWith(duration: _player.duration));
    _broadcastState();
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (!_isLive) _rewindControl,
        if (playing) MediaControl.pause else MediaControl.play,
        if (!_isLive) _fastForwardControl,
        MediaControl.stop,
      ],
      systemActions: {
        if (!_isLive) MediaAction.seek,
        if (!_isLive) MediaAction.seekForward,
        if (!_isLive) MediaAction.seekBackward,
      },
      androidCompactActionIndices: _isLive ? const [0, 1] : const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  @override
  Future<void> play() async {
    try {
      final player = Injector.appInstance.get<CurrentPlayerContract>();
      if (player.playerState == AudioPlayerState.stop) {
        player.playbackSource = 'android_auto';
        try {
          await _playLive(player);
        } finally {
          player.playbackSource = 'app';
        }
        return;
      }
      if (player.playerState == AudioPlayerState.pause) {
        await player.resume();
        return;
      }
    } catch (_) {}
    await _player.play();
  }

  @override
  Future<void> pause() async {
    try {
      Injector.appInstance.get<CurrentPlayerContract>().pause();
    } catch (_) {}
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    try {
      Injector.appInstance.get<CurrentPlayerContract>().stop();
    } catch (_) {}
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() => _seekBy(_seekStep);

  @override
  Future<void> rewind() => _seekBy(-_seekStep);

  Future<void> _seekBy(Duration offset) async {
    if (_isLive) return;
    final duration = _player.duration ?? Duration.zero;
    var target = _player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await _player.seek(target);
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return const [
          MediaItem(id: _tabLive, title: 'Directo', playable: false),
          MediaItem(id: _tabRecent, title: 'Recentes', playable: false),
          MediaItem(id: _tabFavorites, title: 'Favoritos', playable: false),
          MediaItem(id: _tabPlaylist, title: 'Playlist', playable: false),
        ];
      case _tabLive:
        return _liveChildren();
      case _tabRecent:
        return _recentChildren();
      case _tabFavorites:
        return _favoriteChildren();
      case _tabPlaylist:
        return _playlistChildren();
      default:
        if (parentMediaId.startsWith('fav|')) {
          return _favoriteEpisodes(parentMediaId.substring(4));
        }
        return [];
    }
  }

  Future<List<MediaItem>> _liveChildren() async {
    Now? now;
    try {
      final result = await _repository.getLiveBroadcast();
      if (result is Success) now = result.data;
    } catch (_) {}
    _liveNow = now ?? Now.mock();
    return [
      MediaItem(
        id: 'live',
        title: _liveNow!.name,
        artist: 'CUAC FM 103.4',
        artUri: _artUri(_liveNow!.logoUrl),
      ),
    ];
  }

  Future<List<MediaItem>> _recentChildren() async {
    final formatter = DateFormat('dd/MM/yyyy');
    final nowDate = DateTime.now();
    List<TimeTable> timetable = [];
    try {
      final result = await _repository.getTimetableData(
          formatter.format(nowDate.subtract(const Duration(days: 7))),
          formatter.format(nowDate));
      if (result is Success) {
        timetable = List<TimeTable>.from(result.data ?? []);
      }
    } catch (_) {}
    final finished = timetable
        .where((e) =>
            e.type != 'S' && e.end.isBefore(nowDate) && e.rssUrl.isNotEmpty)
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final seen = <String>{};
    final recent = finished.where((e) => seen.add(e.name)).take(20).toList();
    _recentByKey.clear();
    return recent.map((e) {
      final key = 'recent|${e.rssUrl}|${e.start.millisecondsSinceEpoch}';
      _recentByKey[key] = e;
      return MediaItem(
        id: key,
        title: e.name,
        artist: DateFormat('dd/MM').format(e.start),
        artUri: _artUri(e.logoUrl),
      );
    }).toList();
  }

  Future<List<MediaItem>> _favoriteChildren() async {
    final favorites = <Program>[];
    await for (final result
        in _invoker.execute(Injector.appInstance.get<GetFavoritesUseCase>())) {
      if (result is Success) {
        favorites.addAll((result.data ?? [])
            .map((e) => Program.fromFavorite(e))
            .toList()
            .cast<Program>());
      }
    }
    _favoriteByRss.clear();
    return favorites.where((p) => p.rssUrl.isNotEmpty).map((p) {
      _favoriteByRss[p.rssUrl] = p;
      return MediaItem(
        id: 'fav|${p.rssUrl}',
        title: p.name,
        playable: false,
        artUri: _artUri(p.logoUrl),
      );
    }).toList();
  }

  Future<List<MediaItem>> _favoriteEpisodes(String rssUrl) async {
    final episodes = await _episodesFor(rssUrl);
    final program = _favoriteByRss[rssUrl];
    return episodes.take(30).map((ep) {
      return MediaItem(
        id: 'ep|$rssUrl|${ep.audio}',
        title: ep.title,
        artist: program?.name ?? 'CUAC FM',
        artUri: _artUri(program?.logoUrl ?? ''),
      );
    }).toList();
  }

  Future<List<MediaItem>> _playlistChildren() async {
    await _loadPlaylistItems();
    if (_playlistItems.isEmpty) return [];
    return [
      MediaItem(
        id: 'pl_all',
        title: 'Reproducir todo',
        artist: _playlistItems.length == 1
            ? '1 episodio'
            : '${_playlistItems.length} episodios',
      ),
      ..._playlistItems.map((item) {
        return MediaItem(
          id: 'pl|${item['audio']}',
          title: item['title'] ?? '',
          artist: item['programName'] ?? 'CUAC FM',
          artUri: _artUri(item['logoUrl'] ?? ''),
        );
      }),
    ];
  }

  Future<void> _loadPlaylistItems() async {
    _playlistItems = [];
    await for (final result
        in _invoker.execute(Injector.appInstance.get<GetPlaylistUseCase>())) {
      if (result is Success) {
        _playlistItems = List<Map<String, dynamic>>.from(result.data ?? []);
      }
    }
  }

  Future<List<Episode>> _episodesFor(String rssUrl) async {
    final cached = _episodesByRss[rssUrl];
    if (cached != null && cached.isNotEmpty) return cached;
    List<Episode> episodes = [];
    try {
      final result = await _repository.getEpisodes(rssUrl);
      if (result is Success) {
        episodes = List<Episode>.from(result.data ?? []);
      }
    } catch (_) {}
    _episodesByRss[rssUrl] = episodes;
    return episodes;
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    playbackState.add(playbackState.value
        .copyWith(processingState: AudioProcessingState.loading));
    try {
      await _handlePlayFromMediaId(mediaId);
    } finally {
      _broadcastState();
    }
  }

  Future<void> _handlePlayFromMediaId(String mediaId) async {
    final player = Injector.appInstance.get<CurrentPlayerContract>();
    player.playbackSource = 'android_auto';
    try {
      await _dispatchPlayFromMediaId(mediaId, player);
    } finally {
      player.playbackSource = 'app';
    }
  }

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    playbackState.add(playbackState.value
        .copyWith(processingState: AudioProcessingState.loading));
    final player = Injector.appInstance.get<CurrentPlayerContract>();
    player.playbackSource = 'android_auto';
    try {
      await _handleSearch(query, player);
    } finally {
      player.playbackSource = 'app';
      _broadcastState();
    }
  }

  Future<void> _handleSearch(String query, CurrentPlayerContract player) async {
    final normQuery = _normalize(query);
    if (normQuery.isEmpty) {
      await _playLive(player);
      return;
    }
    final program = _matchProgram(normQuery, await _allPrograms());
    if (program == null) {
      await _playLive(player);
      return;
    }
    final episodes = await _episodesFor(program.rssUrl);
    if (episodes.isEmpty) {
      await _playLive(player);
      return;
    }
    final sorted = List<Episode>.from(episodes)
      ..sort((a, b) => b.pubDate.compareTo(a.pubDate));
    await _playEpisode(player, sorted.first, program.name, program.logoUrl);
  }

  static const _searchStopWords = {
    'pon', 'poner', 'reproduce', 'reproducir', 'escoita', 'escoitar', 'abre',
    'o', 'a', 'os', 'as', 'un', 'unha', 'una', 'de', 'do', 'da', 'dos', 'das',
    'en', 'el', 'la', 'los', 'las', 'e', 'y',
    'ultimo', 'ultima', 'novo', 'nova', 'episodio', 'programa', 'capitulo',
    'cuac', 'fm', 'radio',
  };

  Program? _matchProgram(String normQuery, List<Program> programs) {
    final cleaned = _cleanQuery(normQuery);
    final target = cleaned.isNotEmpty ? cleaned : normQuery;
    Program? bySubstring;
    int bySubstringLen = 0;
    Program? byFuzzy;
    double byFuzzyScore = 0;
    for (final p in programs) {
      if (p.rssUrl.isEmpty) continue;
      final name = _normalize(p.name);
      if (name.isEmpty) continue;
      if (normQuery.contains(name) ||
          name.contains(normQuery) ||
          (cleaned.isNotEmpty &&
              (cleaned.contains(name) || name.contains(cleaned)))) {
        if (name.length > bySubstringLen) {
          bySubstringLen = name.length;
          bySubstring = p;
        }
        continue;
      }
      if (target.length >= 4) {
        final cleanedName = _cleanQuery(name);
        final score = math.max(
          _similarity(target, name),
          cleanedName.isEmpty ? 0.0 : _similarity(target, cleanedName),
        );
        if (score > byFuzzyScore) {
          byFuzzyScore = score;
          byFuzzy = p;
        }
      }
    }
    if (bySubstring != null) return bySubstring;
    if (byFuzzy != null && byFuzzyScore >= 0.6) return byFuzzy;
    return null;
  }

  String _cleanQuery(String normQuery) {
    return normQuery
        .split(' ')
        .where((t) => t.isNotEmpty && !_searchStopWords.contains(t))
        .join(' ');
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final distance = _levenshtein(a, b);
    final maxLen = math.max(a.length, b.length);
    return 1 - distance / maxLen;
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    var prev = List<int>.generate(t.length + 1, (i) => i);
    var curr = List<int>.filled(t.length + 1, 0);
    for (var i = 0; i < s.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        curr[j + 1] = math.min(
          math.min(curr[j] + 1, prev[j + 1] + 1),
          prev[j] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[t.length];
  }

  Future<List<Program>> _allPrograms() async {
    if (_allProgramsCache.isNotEmpty) return _allProgramsCache;
    try {
      final result = await _repository.getAllPodcasts();
      if (result is Success) {
        _allProgramsCache = List<Program>.from(result.data ?? []);
      }
    } catch (_) {}
    return _allProgramsCache;
  }

  String _normalize(String input) {
    var s = input.toLowerCase();
    const accents = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c',
    };
    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      buffer.write(accents[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _dispatchPlayFromMediaId(
      String mediaId, CurrentPlayerContract player) async {
    if (mediaId == 'live') {
      await _playLive(player);
      return;
    }
    if (mediaId.startsWith('recent|')) {
      final item = _recentByKey[mediaId];
      if (item == null) return;
      final episodes = await _episodesFor(item.rssUrl);
      if (episodes.isEmpty) return;
      final sorted = List<Episode>.from(episodes)
        ..sort((a, b) => (a.pubDate.difference(item.start).inSeconds.abs())
            .compareTo(b.pubDate.difference(item.start).inSeconds.abs()));
      await _playEpisode(player, sorted.first, item.name, item.logoUrl);
      return;
    }
    if (mediaId.startsWith('ep|')) {
      final rest = mediaId.substring(3);
      final sep = rest.indexOf('|');
      if (sep < 0) return;
      final rssUrl = rest.substring(0, sep);
      final audio = rest.substring(sep + 1);
      final episodes = await _episodesFor(rssUrl);
      Episode? episode;
      for (final e in episodes) {
        if (e.audio == audio) episode = e;
      }
      if (episode == null) return;
      final program = _favoriteByRss[rssUrl];
      await _playEpisode(
          player, episode, program?.name ?? episode.title, program?.logoUrl ?? '');
      return;
    }
    if (mediaId == 'pl_all') {
      if (_playlistItems.isEmpty) await _loadPlaylistItems();
      if (_playlistItems.isEmpty) return;
      final item = _playlistItems.first;
      final episode = Episode.fromMap(item);
      await _playEpisode(
          player, episode, item['programName'] ?? episode.title, item['logoUrl'] ?? '');
      return;
    }
    if (mediaId.startsWith('pl|')) {
      final audio = mediaId.substring(3);
      Map<String, dynamic>? item;
      for (final it in _playlistItems) {
        if (it['audio'] == audio) item = it;
      }
      if (item == null) return;
      final episode = Episode.fromMap(item);
      await _playEpisode(
          player, episode, item['programName'] ?? episode.title, item['logoUrl'] ?? '');
    }
  }

  Future<void> _playLive(CurrentPlayerContract player) async {
    var now = _liveNow;
    if (now == null) {
      try {
        final result = await _repository.getLiveBroadcast();
        if (result is Success) now = result.data;
      } catch (_) {}
      now ??= Now.mock();
      _liveNow = now;
    }
    player.isPodcast = false;
    player.now = now;
    player.currentSong = now.name;
    player.currentImage = now.logoUrl;
    if (player.isPlaying()) {
      await player.stopAndPlay();
    } else {
      await player.play();
    }
  }

  Future<void> _playEpisode(CurrentPlayerContract player, Episode episode,
      String programName, String logoUrl) async {
    player.isPodcast = true;
    player.episode = episode;
    player.currentSong = programName;
    player.currentSubtitle = episode.title;
    player.currentImage = logoUrl.isNotEmpty ? logoUrl : _fallbackArt;
    if (player.isPlaying() || player.isPaused()) {
      await player.stopAndPlay();
    } else {
      await player.play();
    }
  }

  Uri _artUri(String url) {
    if (url.isEmpty ||
        url.startsWith('assets/') ||
        url.contains('default-programme-photo')) {
      return Uri.parse(_fallbackArt);
    }
    return Uri.parse(url);
  }
}
