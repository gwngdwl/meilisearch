import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'metadata_service.dart';

class SearchResult {
  final int id;
  final String content;
  final String heRef;
  final int bookId;
  final String bookTitle;
  final int categoryId;
  final String categoryTitle;
  final String? authors;
  final String? formattedContent;

  const SearchResult({
    required this.id,
    required this.content,
    required this.heRef,
    required this.bookId,
    required this.bookTitle,
    required this.categoryId,
    required this.categoryTitle,
    this.authors,
    this.formattedContent,
  });

  factory SearchResult.fromMap(
      Map<String, dynamic> m, MetadataService metadata) {
    final formatted = m['_formatted'] as Map<String, dynamic>?;
    final bookId = (m['bookId'] as num?)?.toInt() ?? 0;
    final categoryId = (m['categoryId'] as num?)?.toInt() ?? 0;

    final bookMeta = metadata.getBook(bookId);

    return SearchResult(
      id: (m['id'] as num).toInt(),
      content: m['content'] as String? ?? '',
      heRef: m['heRef'] as String? ?? '',
      bookId: bookId,
      bookTitle: bookMeta?.title ?? '',
      categoryId: categoryId,
      categoryTitle: metadata.getCategory(categoryId) ?? '',
      authors: bookMeta?.authors ?? '',
      formattedContent: formatted?['content'] as String?,
    );
  }
}

class SearchFacets {
  final Map<String, int> categories;
  final Map<String, int> books;
  const SearchFacets({required this.categories, required this.books});
}

class SearchResponse {
  final List<SearchResult> hits;
  final int totalHits;
  final SearchFacets facets;
  const SearchResponse(
      {required this.hits, required this.totalHits, required this.facets});
}

class SearchService {
  final HttpClient _client = HttpClient()..autoUncompress = false;

  SearchService();

  Future<SearchResponse> search(
    String query,
    MetadataService metadata, {
    int? categoryId,
    int? bookId,
    int? limit,
    int? offset,
  }) async {
    final filters = <String>[];
    if (categoryId != null) {
      filters.add('categoryId = $categoryId');
    }
    if (bookId != null) {
      filters.add('bookId = $bookId');
    }

    final body = jsonEncode({
      'q': query,
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
      if (filters.isNotEmpty) 'filter': filters,
      'facets': ['categoryId', 'bookId'],
      'attributesToHighlight': ['content'],
      'highlightPreTag': '##',
      'highlightPostTag': '##',
    });

    try {
      debugPrint(
          '[SearchService] Sending search request: query="$query", offset=${offset ?? "default"}, limit=${limit ?? "default"}, filters=$filters');
      final req = await _client
          .postUrl(Uri.parse(
              '${AppConfig.meiliUrl}/indexes/${AppConfig.indexName}/search'))
          .timeout(const Duration(seconds: 10));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Accept-Encoding', 'identity'); // no gzip
      req.add(utf8.encode(body));

      final res = await req.close().timeout(const Duration(seconds: 10));
      final responseBody = await utf8.decoder.bind(res).join();

      if (res.statusCode != 200) {
        debugPrint(
            '[SearchService] ERROR: HTTP ${res.statusCode} - $responseBody');
        throw Exception(
            'Search failed with status ${res.statusCode}: $responseBody');
      }

      final map = jsonDecode(responseBody) as Map<String, dynamic>;
      debugPrint(
          '[SearchService] Response OK: estimatedTotalHits=${map["estimatedTotalHits"]}, hits=${(map["hits"] as List?)?.length ?? 0}');

      final hitsRaw =
          (map['hits'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final hits =
          hitsRaw.map((m) => SearchResult.fromMap(m, metadata)).toList();

      final facetDist = map['facetDistribution'] as Map<String, dynamic>? ?? {};
      final catFacetRaw = (facetDist['categoryId'] as Map<String, dynamic>?)
              ?.cast<String, int>() ??
          {};
      final bookFacetRaw =
          (facetDist['bookId'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {};

      final Map<String, int> catFacet = {};
      for (final e in catFacetRaw.entries) {
        final id = int.tryParse(e.key);
        if (id != null) {
          final title = metadata.getCategory(id);
          if (title != null) catFacet[title] = (catFacet[title] ?? 0) + e.value;
        }
      }

      final Map<String, int> bookFacet = {};
      for (final e in bookFacetRaw.entries) {
        final id = int.tryParse(e.key);
        if (id != null) {
          final title = metadata.getBook(id)?.title;
          if (title != null) {
            bookFacet[title] = (bookFacet[title] ?? 0) + e.value;
          }
        }
      }

      return SearchResponse(
        hits: hits,
        totalHits: (map['estimatedTotalHits'] as int?) ?? 0,
        facets: SearchFacets(categories: catFacet, books: bookFacet),
      );
    } catch (e, stackTrace) {
      debugPrint('[SearchService] ERROR during search: $e');
      debugPrint('[SearchService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  void dispose() {
    _client.close(force: true);
  }
}
