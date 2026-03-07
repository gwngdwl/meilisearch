import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/indexing_service.dart';

class IndexingDialog extends StatefulWidget {
  const IndexingDialog({super.key});

  @override
  State<IndexingDialog> createState() => _IndexingDialogState();
}

class _IndexingDialogState extends State<IndexingDialog> {
  late final IndexingService _service = context.read<IndexingService>();
  StreamSubscription<IndexingProgress>? _sub;
  double _fraction = 0;
  String _message = 'מתחיל אינדוקס...';
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startIndexing();
  }

  void _startIndexing() {
    _sub = _service.buildIndex().listen(
      (progress) {
        if (mounted) {
          setState(() {
            _fraction = progress.fraction;
            _message = progress.message;
            _done = progress.done == progress.total && progress.total > 0;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('בניית האינדקס'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'שגיאה: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ] else if (_done) ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  const Text('האינדקס הושלם בהצלחה!'),
                ] else ...[
                  LinearProgressIndicator(
                    value: _fraction == 0 ? null : _fraction,
                  ),
                  const SizedBox(height: 16),
                  Text(_message, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    '${(_fraction * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_done || _error != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_done),
              child: const Text('סגור'),
            ),
        ],
      ),
    );
  }
}
