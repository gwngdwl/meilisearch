import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class BookMetadata {
  final int id;
  final String title;
  final int categoryId;
  final String categoryTitle;
  final String? authors;

  const BookMetadata({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryTitle,
    this.authors,
  });
}

class MetadataService {
  Map<int, BookMetadata> _books = {};
  Map<int, String> _categories = {};

  Future<void> load(String dbPath) async {
    if (!File(dbPath).existsSync()) return;

    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      final rows = db.select('''
        SELECT
            b.id AS bookId,
            b.title AS bookTitle,
            c.id AS categoryId,
            c.title AS categoryTitle,
            GROUP_CONCAT(a.name, ', ') AS authors
        FROM book b
        JOIN category c ON b.categoryId = c.id
        LEFT JOIN book_author ba ON ba.bookId = b.id
        LEFT JOIN author a ON a.id = ba.authorId
        GROUP BY b.id
      ''');

      final newBooks = <int, BookMetadata>{};
      final newCategories = <int, String>{};

      for (final row in rows) {
        final bId = row['bookId'] as int;
        final cId = row['categoryId'] as int;
        newBooks[bId] = BookMetadata(
          id: bId,
          title: row['bookTitle'] as String,
          categoryId: cId,
          categoryTitle: row['categoryTitle'] as String,
          authors: row['authors'] as String?,
        );
        newCategories[cId] = row['categoryTitle'] as String;
      }

      _books = newBooks;
      _categories = newCategories;
    } finally {
      db.close();
    }
  }

  BookMetadata? getBook(int bookId) => _books[bookId];
  String? getCategory(int categoryId) => _categories[categoryId];

  Map<int, BookMetadata> get books => _books;
  Map<int, String> get categories => _categories;
}
