import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import '../config/app_config.dart';

const int _batchSize = 500;

class IndexingProgress {
  final int done;
  final int total;
  final String message;
  const IndexingProgress(this.done, this.total, this.message);
  double get fraction => total == 0 ? 0 : done / total;
}

class IndexingService {
  final AppConfig _config;
  final HttpClient _client = HttpClient()..autoUncompress = false;

  IndexingService(this._config);

  /// Returns true if the Meilisearch seforim index has at least one document.
  Future<bool> isIndexed() async {
    try {
      final req = await _client
          .getUrl(Uri.parse(
              '${AppConfig.meiliUrl}/indexes/${AppConfig.indexName}/stats'))
          .timeout(const Duration(seconds: 5));
      req.headers.set('Accept-Encoding', 'identity');
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return false;
      }
      final body = await utf8.decoder.bind(res).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map['numberOfDocuments'] as int? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Raw HTTP helper — sends a JSON request to Meilisearch and returns the
  /// decoded response body.
  Future<Map<String, dynamic>> _meiliRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    try {
      final req = await _client
          .openUrl(method, Uri.parse('${AppConfig.meiliUrl}$path'))
          .timeout(const Duration(seconds: 60));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Accept-Encoding', 'identity');
      if (body != null) {
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(const Duration(seconds: 60));
      final responseBody = await utf8.decoder.bind(res).join();

      if (res.statusCode >= 400) {
        debugPrint(
            'Meilisearch Error [${res.statusCode}] on $method $path: $responseBody');
        throw HttpException(
            'Meilisearch Error [${res.statusCode}]: $responseBody',
            uri: Uri.parse('${AppConfig.meiliUrl}$path'));
      }

      if (responseBody.isEmpty) return <String, dynamic>{};
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e, st) {
      debugPrint('Exception in _meiliRequest ($method $path): $e\n$st');
      rethrow;
    }
  }

  /// Streams progress events while indexing seforim.db into Meilisearch.
  Stream<IndexingProgress> buildIndex() async* {
    // ── 1. Configure index settings ──────────────────────────────────────
    yield const IndexingProgress(0, 0, 'מגדיר הגדרות אינדקס...');
    try {
      await _meiliRequest('PATCH', '/indexes/${AppConfig.indexName}/settings',
          body: {
            'searchableAttributes': ['content', 'heRef', 'bookTitle'],
            'filterableAttributes': [
              'categoryId',
              'categoryTitle',
              'bookId',
              'bookTitle',
            ],
            'sortableAttributes': ['bookId', 'lineIndex'],
            'displayedAttributes': [
              'id',
              'content',
              'heRef',
              'lineIndex',
              'bookId',
              'bookTitle',
              'categoryId',
              'categoryTitle',
              'authors',
            ],
          });
    } on HttpException catch (e) {
      if (!e.message.contains('[404]')) {
        debugPrint('Failed to configure index settings: $e');
      }
      // 404 means index doesn't exist yet — will be auto-created on first
      // document upload.
    }

    // ── 2. Open the database ─────────────────────────────────────────────
    yield const IndexingProgress(0, 0, 'קורא מסד הנתונים...');

    final dbPath = _config.dbPath;
    if (dbPath == null || !File(dbPath).existsSync()) {
      throw Exception('נתיב מסד הנתונים אינו מוגדר או לא קיים: $dbPath');
    }

    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);

    try {
      // Count total lines
      final countResult = db.select('SELECT COUNT(*) AS cnt FROM line');
      final total = countResult.first['cnt'] as int;
      yield IndexingProgress(
          0, total, 'נמצאו $total שורות. שולח ל-Meilisearch...');

      // ── 3. Fetch and index in batches ────────────────────────────────────
      int done = 0;
      int offset = 0;

      while (true) {
        final rows = db.select('''
          SELECT
              l.id          AS id,
              l.content     AS content,
              l.heRef       AS heRef,
              l.lineIndex   AS lineIndex,
              b.id          AS bookId,
              b.title       AS bookTitle,
              c.id          AS categoryId,
              c.title       AS categoryTitle,
              GROUP_CONCAT(a.name, ', ') AS authors
          FROM line l
          JOIN book b ON l.bookId = b.id
          JOIN category c ON b.categoryId = c.id
          LEFT JOIN book_author ba ON ba.bookId = b.id
          LEFT JOIN author a ON a.id = ba.authorId
          GROUP BY l.id
          LIMIT ? OFFSET ?
        ''', [_batchSize, offset]);

        if (rows.isEmpty) break;

        // Build list of document maps
        final docs = rows.map((row) {
          return <String, dynamic>{
            'id': row['id'],
            'content': row['content'],
            'heRef': row['heRef'],
            'lineIndex': row['lineIndex'],
            'bookId': row['bookId'],
            'bookTitle': row['bookTitle'],
            'categoryId': row['categoryId'],
            'categoryTitle': row['categoryTitle'],
            'authors': row['authors'],
          };
        }).toList();

        try {
          await _meiliRequest(
            'POST',
            '/indexes/${AppConfig.indexName}/documents?primaryKey=id',
            body: docs,
          );
        } catch (e, st) {
          debugPrint(
              'Failed to index batch at offset $offset (size: ${docs.length}): $e\n$st');
          rethrow;
        }

        done += rows.length;
        offset += _batchSize;
        yield IndexingProgress(
          done,
          total,
          'הועברו $done מתוך $total שורות...',
        );
      }

      yield IndexingProgress(total, total, 'האינדקס הושלם!');
    } finally {
      db.close();
    }
  }
}
