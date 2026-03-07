import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String serverHost = '127.0.0.1';
  static const int serverPort = 7700;
  static String get meiliUrl => 'http://$serverHost:$serverPort';
  static const String indexName = 'seforim';

  static const String _dbPathKey = 'db_path';

  final SharedPreferences _prefs;

  AppConfig(this._prefs);

  String? get dbPath => _prefs.getString(_dbPathKey);

  Future<void> setDbPath(String path) async {
    await _prefs.setString(_dbPathKey, path);
  }
}
