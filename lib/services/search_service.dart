import 'dart:convert';
import 'dart:io';

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

  factory SearchResult.fromMap(Map<String, dynamic> m) {
    final formatted = m['_formatted'] as Map<String, dynamic>?;
    return SearchResult(
      id: (m['id'] as num).toInt(),
      content: m['content'] as String? ?? '',
      heRef: m['heRef'] as String? ?? '',
      bookId: (m['bookId'] as num?)?.toInt() ?? 0,
      bookTitle: m['bookTitle'] as String? ?? '',
      categoryId: (m['categoryId'] as num?)?.toInt() ?? 0,
      categoryTitle: m['categoryTitle'] as String? ?? '',
      authors: m['authors'] as String?,
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
  static const String _baseUrl = 'http://127.0.0.1:7700';
  static const String _indexName = 'seforim';

  Future<SearchResponse> search(
    String query, {
    String? categoryTitle,
    String? bookTitle,
    int limit = 20,
    int offset = 0,
  }) async {
    final filters = <String>[];
    if (categoryTitle != null && categoryTitle.isNotEmpty) {
      filters.add('categoryTitle = "${categoryTitle.replaceAll('"', '\\"')}"');
    }
    if (bookTitle != null && bookTitle.isNotEmpty) {
      filters.add('bookTitle = "${bookTitle.replaceAll('"', '\\"')}"');
    }

    final body = jsonEncode({
      'q': query,
      'limit': limit,
      'offset': offset,
      if (filters.isNotEmpty) 'filter': filters,
      'facets': ['categoryTitle', 'bookTitle'],
      'attributesToHighlight': ['content'],
      'highlightPreTag': '##',
      'highlightPostTag': '##',
    });

    final client = HttpClient();
    client.autoUncompress = false; // we set Accept-Encoding: identity, no gzip
    try {
      print(
          '[SearchService] Sending search request: query="$query", offset=$offset, limit=$limit, filters=$filters');
      final req = await client
          .postUrl(Uri.parse('$_baseUrl/indexes/$_indexName/search'))
          .timeout(const Duration(seconds: 10));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Accept-Encoding', 'identity'); // no gzip
      req.add(utf8.encode(body));

      final res = await req.close().timeout(const Duration(seconds: 10));
      final responseBody = await utf8.decoder.bind(res).join();

      if (res.statusCode != 200) {
        print('[SearchService] ERROR: HTTP ${res.statusCode} - $responseBody');
        throw Exception(
            'Search failed with status ${res.statusCode}: $responseBody');
      }

      final map = jsonDecode(responseBody) as Map<String, dynamic>;
      print(
          '[SearchService] Response OK: estimatedTotalHits=${map['estimatedTotalHits']}, hits=${(map['hits'] as List?)?.length ?? 0}');

      final hitsRaw =
          (map['hits'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final hits = hitsRaw.map(SearchResult.fromMap).toList();

      final facetDist = map['facetDistribution'] as Map<String, dynamic>? ?? {};
      final catFacet = (facetDist['categoryTitle'] as Map<String, dynamic>?)
              ?.cast<String, int>() ??
          {};
      final bookFacet = (facetDist['bookTitle'] as Map<String, dynamic>?)
              ?.cast<String, int>() ??
          {};

      return SearchResponse(
        hits: hits,
        totalHits: (map['estimatedTotalHits'] as int?) ?? 0,
        facets: SearchFacets(categories: catFacet, books: bookFacet),
      );
    } catch (e, stackTrace) {
      print('[SearchService] ERROR during search: $e');
      print('[SearchService] Stack trace: $stackTrace');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
