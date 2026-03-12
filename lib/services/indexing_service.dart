import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import '../config/app_config.dart';

const int _batchSize = 10000;
const int _maxValuesPerFacet = 1000000;
const int _maxTotalHits = 1000000;

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

  Future<void> _waitForTask(int taskUid) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final task = await _meiliRequest('GET', '/tasks/$taskUid');
      final status = task['status'] as String? ?? '';
      if (status == 'succeeded') return;
      if (status == 'failed' || status == 'canceled') {
        throw Exception(
            'Meilisearch task $taskUid ended with status $status: ${task['error'] ?? task}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    throw TimeoutException('Timed out waiting for Meilisearch task $taskUid');
  }

  Future<void> ensureSearchSettings() async {
    var needsUpdate = true;
    try {
      final settings =
          await _meiliRequest('GET', '/indexes/${AppConfig.indexName}/settings');
      final faceting =
          (settings['faceting'] as Map<String, dynamic>?) ?? const {};
      final pagination =
          (settings['pagination'] as Map<String, dynamic>?) ?? const {};
      needsUpdate = faceting['maxValuesPerFacet'] != _maxValuesPerFacet ||
          pagination['maxTotalHits'] != _maxTotalHits;
    } on HttpException catch (e) {
      if (!e.message.contains('[404]')) rethrow;
    }

    if (!needsUpdate) return;

    final response =
        await _meiliRequest('PATCH', '/indexes/${AppConfig.indexName}/settings',
            body: {
          'faceting': {'maxValuesPerFacet': _maxValuesPerFacet},
          'pagination': {'maxTotalHits': _maxTotalHits},
        });

    final taskUid = (response['taskUid'] as num?)?.toInt();
    if (taskUid != null) {
      await _waitForTask(taskUid);
    }
  }

  /// Streams progress events while indexing seforim.db into Meilisearch.
  Stream<IndexingProgress> buildIndex() async* {
    // ── 1. Configure index settings ──────────────────────────────────────
    yield const IndexingProgress(0, 0, 'מגדיר הגדרות אינדקס...');
    try {
      await _meiliRequest('PATCH', '/indexes/${AppConfig.indexName}/settings',
          body: {
            'searchableAttributes': ['content', 'heRef'],
            'filterableAttributes': [
              'categoryId',
              'bookId',
            ],
            'sortableAttributes': ['bookId', 'lineIndex'],
            'displayedAttributes': [
              'id',
              'content',
              'heRef',
              'lineIndex',
              'bookId',
              'categoryId',
            ],
            'stopWords': [
              'של', 'את', 'על', 'אל', 'מן', 'כל', 'עם', 'גם', 'זה', 'לא', 'כן', 'או', 'רק', 'אך', 'אלא', 'אם', 'הוא', 'היא', 'הם', 'הן', 'אשר', 'כי', 'עד', 'בין', 'כמו', 'אני', 'אתה', 'אנחנו', 'אתם', 'אף', 'כדי', 'מה', 'מי', 'יש', 'אין'
            ],
            'faceting': {'maxValuesPerFacet': _maxValuesPerFacet},
            'pagination': {'maxTotalHits': _maxTotalHits},
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
      int lastId = 0;

      while (true) {
        final rows = db.select('''
          SELECT
              l.id          AS id,
              l.content     AS content,
              l.heRef       AS heRef,
              l.lineIndex   AS lineIndex,
              b.id          AS bookId,
              b.categoryId  AS categoryId
          FROM line l
          JOIN book b ON l.bookId = b.id
          WHERE l.id > ?
          ORDER BY l.id ASC
          LIMIT ?
        ''', [lastId, _batchSize]);

        if (rows.isEmpty) break;

        lastId = rows.last['id'] as int;

        // Build list of document maps
        final docs = rows.map((row) {
          return <String, dynamic>{
            'id': row['id'],
            'content': row['content'],
            'heRef': row['heRef'],
            'lineIndex': row['lineIndex'],
            'bookId': row['bookId'],
            'categoryId': row['categoryId'],
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
              'Failed to index batch ending after lastId $lastId (size: ${docs.length}): $e\n$st');
          rethrow;
        }

        done += rows.length;
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
