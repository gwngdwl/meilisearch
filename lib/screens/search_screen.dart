import 'dart:async';
import 'package:flutter/material.dart';
import '../services/search_service.dart';
import '../services/indexing_service.dart';
import '../widgets/indexing_dialog.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final SearchService _searchService = SearchService();
  final IndexingService _indexingService = IndexingService();
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;

  List<SearchResult> _results = [];
  int _totalHits = 0;
  bool _loading = false;
  bool _indexed = false;
  bool _checkingIndex = true;

  // Filters
  String? _selectedCategory;
  String? _selectedBook;
  Map<String, int> _categoryFacets = {};
  Map<String, int> _bookFacets = {};

  int _offset = 0;
  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _checkIndexed();
  }

  Future<void> _checkIndexed() async {
    final indexed = await _indexingService.isIndexed();
    if (mounted) {
      setState(() {
        _indexed = indexed;
        _checkingIndex = false;
      });
    }
    if (indexed) _runSearch();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _offset = 0;
      _runSearch();
    });
  }

  Future<void> _runSearch() async {
    if (!_indexed) return;
    setState(() => _loading = true);
    try {
      final response = await _searchService.search(
        _queryController.text,
        categoryTitle: _selectedCategory,
        bookTitle: _selectedBook,
        limit: _limit,
        offset: _offset,
      );
      if (mounted) {
        setState(() {
          _results =
              _offset == 0 ? response.hits : [..._results, ...response.hits];
          _totalHits = response.totalHits;
          _categoryFacets = response.facets.categories;
          _bookFacets = response.facets.books;
          _loading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[SearchScreen] ERROR in _runSearch: $e');
      debugPrint('[SearchScreen] Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאת חיפוש: $e')));
      }
    }
  }

  Future<void> _openIndexingDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IndexingDialog(),
    );
    if (result == true) {
      setState(() => _indexed = true);
      _runSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חיפוש בספרים'),
          actions: [
            IconButton(
              icon: const Icon(Icons.storage),
              tooltip: 'בנה/עדכן אינדקס',
              onPressed: _openIndexingDialog,
            ),
          ],
        ),
        body: _checkingIndex
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchBar(),
                  if (!_indexed) _buildNoIndexBanner(),
                  if (_indexed) _buildFiltersRow(),
                  if (_indexed) _buildResultsCount(),
                  if (_indexed) Expanded(child: _buildResultsList()),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _queryController,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'חפש בטקסט...',
          prefixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search),
          suffixIcon: _queryController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _queryController.clear();
                    _offset = 0;
                    _runSearch();
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  Widget _buildNoIndexBanner() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 8),
          const Expanded(child: Text('האינדקס עדיין לא נבנה.')),
          ElevatedButton.icon(
            icon: const Icon(Icons.build),
            label: const Text('צור אינדקס'),
            onPressed: _openIndexingDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    final categories = _categoryFacets.keys.toList()..sort();
    final books = _bookFacets.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'קטגוריה',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('הכל')),
                ...categories.map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedCategory = v;
                  _selectedBook = null;
                  _offset = 0;
                });
                _runSearch();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedBook,
              decoration: const InputDecoration(
                labelText: 'ספר',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('הכל')),
                ...books.map(
                  (b) => DropdownMenuItem(
                    value: b,
                    child: Text(b, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedBook = v;
                  _offset = 0;
                });
                _runSearch();
              },
            ),
          ),
          if (_selectedCategory != null || _selectedBook != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.filter_alt_off),
                tooltip: 'נקה פילטרים',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                    _selectedBook = null;
                    _offset = 0;
                  });
                  _runSearch();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsCount() {
    if (_totalHits == 0 && !_loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${_totalHits.toString()} תוצאות',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty && !_loading) {
      return const Center(
        child: Text('לא נמצאו תוצאות', style: TextStyle(fontSize: 18)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _results.length + (_offset + _limit < _totalHits ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i == _results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  _offset += _limit;
                  _runSearch();
                },
                child: const Text('טען עוד'),
              ),
            ),
          );
        }
        return _buildResultCard(_results[i]);
      },
    );
  }

  Widget _buildResultCard(SearchResult r) {
    final display = r.formattedContent ?? r.content;
    // Split by highlight markers ##...##
    final spans = _buildHighlightedSpans(display);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    r.bookTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.heRef,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              textDirection: TextDirection.rtl,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: spans,
              ),
            ),
            if (r.authors != null && r.authors!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                r.authors!,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<TextSpan> _buildHighlightedSpans(String text) {
    final parts = text.split('##');
    List<TextSpan> spans = [];
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      if (i % 2 == 1) {
        // Highlighted part (between ## markers)
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              backgroundColor: Colors.yellow.shade300,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: parts[i]));
      }
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }
}
