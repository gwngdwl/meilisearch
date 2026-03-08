import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/indexing_state.dart';

class IndexingDialog extends StatefulWidget {
  const IndexingDialog({super.key});

  @override
  State<IndexingDialog> createState() => _IndexingDialogState();
}

class _IndexingDialogState extends State<IndexingDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IndexingState>().startIndexing();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<IndexingState>(
        builder: (context, state, child) {
          return AlertDialog(
            title: const Text('בניית האינדקס'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.error != null) ...[
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'שגיאה: ${state.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ] else if (state.done) ...[
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      const Text('האינדקס הושלם בהצלחה!'),
                    ] else ...[
                      LinearProgressIndicator(
                        value: state.fraction == 0 ? null : state.fraction,
                      ),
                      const SizedBox(height: 16),
                      Text(state.message, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        '${(state.fraction * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (state.done || state.error != null)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(state.done),
                  child: const Text('סגור'),
                ),
            ],
          );
        },
      ),
    );
  }
}
