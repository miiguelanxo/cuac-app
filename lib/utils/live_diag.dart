import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LiveDiag {
  static File? _file;
  static bool _resolved = false;
  static Future<void> _chain = Future.value();

  static void log(String msg) {
    final line = '${DateTime.now().toIso8601String()} $msg\n';
    print('[CUACLIVE] $msg');
    _chain = _chain.then((_) => _append(line)).catchError((_) {});
  }

  static Future<void> _append(String line) async {
    if (!_resolved) {
      _resolved = true;
      try {
        final dir = await getExternalStorageDirectory();
        if (dir != null) _file = File('${dir.path}/cuaclive.log');
      } catch (_) {}
    }
    final f = _file;
    if (f == null) return;
    if (await f.exists() && await f.length() > 2000000) {
      try {
        final content = await f.readAsString();
        final half = content.substring(content.length ~/ 2);
        final nl = half.indexOf('\n');
        await f.writeAsString(nl >= 0 ? half.substring(nl + 1) : half);
      } catch (_) {
        await f.writeAsString('');
      }
    }
    await f.writeAsString(line, mode: FileMode.append, flush: true);
  }
}
