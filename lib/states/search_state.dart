import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/search_service.dart';
import '../services/indexing_service.dart';
import '../services/metadata_service.dart';
import '../config/app_config.dart';

class SearchState extends ChangeNotifier {
  final SearchService _searchService;
  final IndexingService _indexingService;
  final AppConfig _appConfig;
  final MetadataService _metadataService = MetadataService();

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

  static const int _searchChunkSize = 1000;
  int _searchVersion = 0;
  bool _searchSettingsEnsured = false;

  String? _error;
  String? get error => _error;

  void checkIndexed() async {
    _checkingIndex = true;
    notifyListeners();
    final dbPath = _appConfig.dbPath;
    if (dbPath != null) {
      await _metadataService.load(dbPath);
    }
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
    notifyListeners();
    runSearch();
  }

  void selectBook(String? book) {
    _selectedBook = book;
    notifyListeners();
    runSearch();
  }

  void clearFilters() {
    _selectedCategory = null;
    _selectedBook = null;
    notifyListeners();
    runSearch();
  }

  void clearQuery() {
    queryController.clear();
    notifyListeners();
    runSearch();
  }

  Future<void> runSearch() async {
    if (!_indexed) return;
    final searchVersion = ++_searchVersion;
    final query = queryController.text.trim();
    final hasCategoryFilter =
        _selectedCategory != null && _selectedCategory!.isNotEmpty;
    final hasBookFilter = _selectedBook != null && _selectedBook!.isNotEmpty;

    _loading = true;
    _error = null;
    _results = [];
    _totalHits = 0;
    _categoryFacets = {};
    _bookFacets = {};
    notifyListeners();

    if (query.isEmpty && !hasCategoryFilter && !hasBookFilter) {
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      if (!_searchSettingsEnsured) {
        await _indexingService.ensureSearchSettings();
        if (searchVersion != _searchVersion) return;
        _searchSettingsEnsured = true;
      }

      final int? categoryId = _selectedCategory != null
          ? _metadataService.categories.entries
              .where((e) => e.value == _selectedCategory)
              .map((e) => e.key)
              .firstOrNull
          : null;
      final int? bookId = _selectedBook != null
          ? _metadataService.books.entries
              .where((e) => e.value.title == _selectedBook)
              .map((e) => e.key)
              .firstOrNull
          : null;

      var offset = 0;
      var totalHits = 0;
      final allHits = <SearchResult>[];
      Map<String, int> categoryFacets = {};
      Map<String, int> bookFacets = {};

      while (true) {
        final response = await _searchService.search(
          query,
          _metadataService,
          categoryId: categoryId,
          bookId: bookId,
          limit: _searchChunkSize,
          offset: offset,
        );
        if (searchVersion != _searchVersion) return;

        if (offset == 0) {
          totalHits = response.totalHits;
          categoryFacets = response.facets.categories;
          bookFacets = response.facets.books;
        }

        if (response.hits.isEmpty) break;

        allHits.addAll(response.hits);
        _results = List<SearchResult>.unmodifiable(allHits);
        _totalHits = totalHits > allHits.length ? totalHits : allHits.length;
        _categoryFacets = categoryFacets;
        _bookFacets = bookFacets;
        notifyListeners();

        offset += response.hits.length;
        if (response.hits.length < _searchChunkSize) break;
      }

      if (searchVersion != _searchVersion) return;

      _results = List<SearchResult>.unmodifiable(allHits);
      _totalHits = totalHits > allHits.length ? totalHits : allHits.length;
      _categoryFacets = categoryFacets;
      _bookFacets = bookFacets;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (searchVersion != _searchVersion) return;
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
