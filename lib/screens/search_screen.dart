import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../states/search_state.dart';
import '../config/app_config.dart';
import '../services/search_service.dart';
import '../widgets/indexing_dialog.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  Future<void> _openIndexingDialog(BuildContext context) async {
    final state = context.read<SearchState>();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IndexingDialog(),
    );
    if (result == true) {
      state.setIndexed(true);
    }
  }

  Future<void> _pickDatabase(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'בחר קובץ מסד נתונים (seforim.db)',
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
    );
    if (!context.mounted) return;
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final config = context.read<AppConfig>();
      await config.setDbPath(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('נתיב מסד הנתונים עודכן: $path')),
        );
        // After db update, let's re-check indexing.
        context.read<SearchState>().checkIndexed();
      }
    }
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
              icon: const Icon(Icons.settings),
              tooltip: 'בחר מסד נתונים',
              onPressed: () => _pickDatabase(context),
            ),
            IconButton(
              icon: const Icon(Icons.storage),
              tooltip: 'בנה/עדכן אינדקס',
              onPressed: () => _openIndexingDialog(context),
            ),
          ],
        ),
        body: Consumer<SearchState>(
          builder: (context, state, child) {
            if (state.checkingIndex) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                _buildSearchBar(context, state),
                if (!state.indexed) _buildNoIndexBanner(context),
                if (state.indexed) _buildFiltersRow(context, state),
                if (state.indexed) _buildResultsCount(context, state),
                if (state.indexed)
                  Expanded(child: _buildResultsList(context, state)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, SearchState state) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: state.queryController,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'חפש בטקסט...',
          prefixIcon: state.loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search),
          suffixIcon: state.queryController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: state.clearQuery,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
        ),
        onChanged: state.onQueryChanged,
      ),
    );
  }

  Widget _buildNoIndexBanner(BuildContext context) {
    final config = context.read<AppConfig>();
    final bool hasDb = config.dbPath != null;

    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasDb
                      ? 'האינדקס עדיין לא נבנה. במסד: ${config.dbPath}'
                      : 'לא נבחר מסד נתונים. אנא בחר קובץ db קודם.',
                ),
              ),
              if (hasDb)
                ElevatedButton.icon(
                  icon: const Icon(Icons.build),
                  label: const Text('צור אינדקס'),
                  onPressed: () => _openIndexingDialog(context),
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('בחר קובץ'),
                  onPressed: () => _pickDatabase(context),
                ),
            ],
          ),
          if (context.watch<SearchState>().error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'שגיאה: ${context.watch<SearchState>().error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow(BuildContext context, SearchState state) {
    final categories = state.categoryFacets.keys.toList()..sort();
    final books = state.bookFacets.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: state.selectedCategory,
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
              onChanged: state.selectCategory,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: state.selectedBook,
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
              onChanged: state.selectBook,
            ),
          ),
          if (state.selectedCategory != null || state.selectedBook != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.filter_alt_off),
                tooltip: 'נקה פילטרים',
                onPressed: state.clearFilters,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsCount(BuildContext context, SearchState state) {
    if (state.totalHits == 0 && !state.loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${state.totalHits} תוצאות',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildResultsList(BuildContext context, SearchState state) {
    if (state.results.isEmpty && !state.loading) {
      if (state.error != null) {
        return Center(
          child: Text('שגיאה: ${state.error}',
              style: const TextStyle(color: Colors.red)),
        );
      }
      return const Center(
        child: Text('לא נמצאו תוצאות', style: TextStyle(fontSize: 18)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: state.results.length +
          (state.results.length < state.totalHits ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i == state.results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: ElevatedButton(
                onPressed: state.loading ? null : state.loadMore,
                child: state.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('טען עוד'),
              ),
            ),
          );
        }
        return _buildResultCard(context, state.results[i]);
      },
    );
  }

  Widget _buildResultCard(BuildContext context, SearchResult r) {
    final display = r.formattedContent ?? r.content;
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
