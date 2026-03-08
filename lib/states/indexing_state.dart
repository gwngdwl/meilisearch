import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/indexing_service.dart';

class IndexingState extends ChangeNotifier {
  final IndexingService _indexingService;

  StreamSubscription<IndexingProgress>? _sub;

  double _fraction = 0;
  double get fraction => _fraction;

  String _message = 'מתחיל אינדוקס...';
  String get message => _message;

  bool _done = false;
  bool get done => _done;

  String? _error;
  String? get error => _error;

  IndexingState(this._indexingService);

  void startIndexing() {
    _fraction = 0;
    _message = 'מתחיל אינדוקס...';
    _done = false;
    _error = null;
    notifyListeners();

    _sub?.cancel();
    _sub = _indexingService.buildIndex().listen(
      (progress) {
        _fraction = progress.fraction;
        _message = progress.message;
        _done = progress.done == progress.total && progress.total > 0;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  void reset() {
    _sub?.cancel();
    _fraction = 0;
    _message = 'מתחיל אינדוקס...';
    _done = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
