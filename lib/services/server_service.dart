import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';

class ServerService {
  ServerService();

  Process? _process;

  String get baseUrl => AppConfig.meiliUrl;

  Future<void> start() async {
    // Check if already running
    if (await _isRunning()) return;

    final exePath = _findExe();
    if (exePath == null) {
      throw Exception('Meilisearch EXE not found in bin/');
    }

    final dataDir = p.join(p.dirname(exePath), '..', 'meili_data');
    Directory(dataDir).createSync(recursive: true);

    _process = await Process.start(exePath, [
      '--db-path',
      dataDir,
      '--http-addr',
      '${AppConfig.serverHost}:${AppConfig.serverPort}',
      '--no-analytics',
    ]);

    // Discard process stdout/stderr completely — do NOT use utf8.decoder
    // as the process may output non-UTF-8 bytes (ASCII art / box drawing chars)
    _process!.stdout.drain<void>().ignore();
    _process!.stderr.drain<void>().ignore();

    // Wait until healthy (up to 15 sec)
    const maxWait = Duration(seconds: 15);
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isRunning()) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    throw Exception('Meilisearch did not start within 15 seconds');
  }

  /// Check if Meilisearch is running by making a raw HTTP GET /health request.
  /// Uses dart:io HttpClient directly (no dio) to avoid gzip/encoding issues.
  Future<bool> _isRunning() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.autoUncompress = false; // we drain body raw, don't decode
      final req = await client
          .getUrl(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      req.headers.set('Accept-Encoding', 'identity');
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain<void>(); // consume and discard body
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<bool> get isRunning => _isRunning();

  void stop() {
    _process?.kill();
    _process = null;
  }

  String? _findExe() {
    // Relative to the executable (release) or current dir (debug)
    final candidates = [
      p.join(
        Directory.current.path,
        'bin',
        'meilisearch-enterprise-windows-amd64.exe',
      ),
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'bin',
        'meilisearch-enterprise-windows-amd64.exe',
      ),
      p.join(
        p.dirname(Platform.resolvedExecutable),
        '..',
        '..',
        '..',
        '..',
        '..',
        'bin',
        'meilisearch-enterprise-windows-amd64.exe',
      ),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return p.normalize(c);
    }
    return null;
  }
}
