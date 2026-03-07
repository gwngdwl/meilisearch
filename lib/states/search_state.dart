import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/search_service.dart';
import '../services/indexing_service.dart';
import '../config/app_config.dart';

class SearchState extends ChangeNotifier {
  final SearchService _searchService;
  final IndexingService _indexingService;
  final AppConfig _appConfig;

  SearchState(this._searchService, this._indexingService, this._appConfig);

  final TextEditingController queryController = TextEditingController();
  Timer? _debounce;

  List<SearchResult> _results = [];
  List<SearchResult> get results => _results;

  int _totalHits = 0;
  int get totalHits => _totalHits;

  bool _loading = false;
  bool get loading => _loading;

  bool _indexed = false;
  bool get indexed => _indexed;

  bool _checkingIndex = true;
  bool get checkingIndex => _checkingIndex;

  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  String? _selectedBook;
  String? get selectedBook => _selectedBook;

  Map<String, int> _categoryFacets = {};
  Map<String, int> get categoryFacets => _categoryFacets;

  Map<String, int> _bookFacets = {};
  Map<String, int> get bookFacets => _bookFacets;

  int _offset = 0;
  static const int limit = 20;

  String? _error;
  String? get error => _error;

  void checkIndexed() async {
    _checkingIndex = true;
    notifyListeners();
    _indexed = await _indexingService.isIndexed();
    _checkingIndex = false;
    notifyListeners();
    if (_indexed) runSearch();
  }

  Future<String?> pickDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'בחר קובץ מסד נתונים (seforim.db)',
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await _appConfig.setDbPath(path);
      checkIndexed();
      return path;
    }
    return null;
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _offset = 0;
      runSearch();
    });
  }

  void setIndexed(bool value) {
    _indexed = value;
    notifyListeners();
    if (value) {
      runSearch();
    }
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedBook = null;
    _offset = 0;
    notifyListeners();
    runSearch();
  }

  void selectBook(String? book) {
    _selectedBook = book;
    _offset = 0;
    notifyListeners();
    runSearch();
  }

  void clearFilters() {
    _selectedCategory = null;
    _selectedBook = null;
    _offset = 0;
    notifyListeners();
    runSearch();
  }

  void clearQuery() {
    queryController.clear();
    _offset = 0;
    notifyListeners();
    runSearch();
  }

  void loadMore() {
    _offset += limit;
    runSearch();
  }

  Future<void> runSearch() async {
    if (!_indexed) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _searchService.search(
        queryController.text,
        categoryTitle: _selectedCategory,
        bookTitle: _selectedBook,
        limit: limit,
        offset: _offset,
      );

      _results = _offset == 0 ? response.hits : [..._results, ...response.hits];
      _totalHits = response.totalHits;
      _categoryFacets = response.facets.categories;
      _bookFacets = response.facets.books;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    queryController.dispose();
    super.dispose();
  }
}
