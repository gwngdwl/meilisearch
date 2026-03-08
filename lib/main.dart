import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'services/server_service.dart';
import 'services/search_service.dart';
import 'services/indexing_service.dart';
import 'screens/search_screen.dart';
import 'states/search_state.dart';
import 'states/server_state.dart';
import 'states/indexing_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all unhandled async errors to prevent app crash
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== Unhandled error: $error\n$stack ===');
    return true; // Handled — do not crash
  };
  FlutterError.onError = (details) => FlutterError.presentError(details);

  final prefs = await SharedPreferences.getInstance();
  final config = AppConfig(prefs);
  final serverService = ServerService();
  final searchService = SearchService();
  final indexingService = IndexingService(config);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: config),
        Provider<ServerService>.value(value: serverService),
        Provider<SearchService>.value(value: searchService),
        Provider<IndexingService>.value(value: indexingService),
        ChangeNotifierProvider(
          create: (_) => ServerState(serverService)..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => IndexingState(indexingService),
        ),
        ChangeNotifierProvider(
          create: (_) => SearchState(searchService, indexingService, config)
            ..checkIndexed(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      if (mounted) context.read<ServerState>().stop();
    }
  }

  @override
  void dispose() {
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
      home: Consumer<ServerState>(
        builder: (context, state, child) {
          if (state.isReady) {
            return const SearchScreen();
          }
          return _SplashScreen(status: state.status, isError: state.hasError);
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String status;
  final bool isError;
  const _SplashScreen({required this.status, this.isError = false});

  @override
  Widget build(BuildContext context) {
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
