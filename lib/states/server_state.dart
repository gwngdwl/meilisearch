import 'package:flutter/foundation.dart';
import '../services/server_service.dart';

class ServerState extends ChangeNotifier {
  final ServerService _serverService;

  String _status = 'מאתחל שרת...';
  String get status => _status;

  bool _isReady = false;
  bool get isReady => _isReady;

  bool _hasError = false;
  bool get hasError => _hasError;

  ServerState(this._serverService);

  Future<void> initialize() async {
    try {
      await _serverService.start();
      _isReady = true;
      _hasError = false;
      notifyListeners();
    } catch (e) {
      _status = 'שגיאה בהפעלת השרת:\n$e';
      _isReady = false;
      _hasError = true;
      notifyListeners();
    }
  }

  void stop() {
    _serverService.stop();
  }
}
