import 'dart:ui';
import 'package:flutter/material.dart';
import 'services/server_service.dart';
import 'screens/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all unhandled async errors to prevent app crash
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== Unhandled error: $error\n$stack ===');
    return true; // Handled — do not crash
  };
  FlutterError.onError = (details) => FlutterError.presentError(details);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ServerService _server = ServerService();
  String _serverStatus = 'מאתחל שרת...';
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      await _server.start();
      if (mounted) setState(() => _serverReady = true);
    } catch (e) {
      if (mounted) setState(() => _serverStatus = 'שגיאה בהפעלת השרת:\n$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) _server.stop();
  }

  @override
  void dispose() {
    _server.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'חיפוש בספרים',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: _serverReady
          ? const SearchScreen()
          : _SplashScreen(status: _serverStatus),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String status;
  const _SplashScreen({required this.status});

  @override
  Widget build(BuildContext context) {
    final isError = status.startsWith('שגיאה');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isError)
                const CircularProgressIndicator()
              else
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isError ? Colors.red : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
