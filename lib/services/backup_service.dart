import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants.dart';
import 'database_service.dart';

/// Raised when an import file cannot be trusted. The message is shown to the
/// user, so it explains the problem in plain language.
class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whole-book export and import as a single JSON file.
///
/// The export is a straight dump of every table, so a restore reproduces the
/// book exactly — including ids, so orders keep pointing at their medicines.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Bumped only if the file layout changes in a way importers must know about.
  static const int formatVersion = 1;

  static const List<String> _tables = [
    'patients',
    'medicines',
    'dose_assignments',
    'pharmacies',
    'orders',
    'order_items',
    'medicine_events',
  ];

  final DatabaseService _dbs = DatabaseService.instance;

  // ------------------------------------------------------------------ export

  /// Builds the backup document.
  Future<Map<String, Object?>> buildExport() async {
    final db = await _dbs.database;

    final data = <String, Object?>{};
    for (final table in _tables) {
      // db.query returns read-only row views; copy them into plain maps so the
      // document is a normal, mutable JSON structure for any caller.
      final rows = await db.query(table);
      data[table] = [
        for (final row in rows) Map<String, Object?>.from(row),
      ];
    }

    return {
      'app': 'Medstock',
      'formatVersion': formatVersion,
      'schemaVersion': K.dbVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': {
        for (final t in _tables) t: (data[t] as List).length,
      },
      'data': data,
    };
  }

  /// Writes the backup to a file in the app's documents directory and returns
  /// it, ready to be shared. Pretty-printed so it is readable and diffable.
  Future<File> exportToFile() async {
    final doc = await buildExport();
    final json = const JsonEncoder.withIndent('  ').convert(doc);

    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'medstock-backup-$stamp.json'));
    await file.writeAsString(json, flush: true);
    return file;
  }

  // ------------------------------------------------------------------ import

  /// Summary of what a file contains, so the user can confirm before it is
  /// applied. Parsing never touches the database.
  Future<BackupPreview> inspect(String jsonText) async {
    final Object? parsed;
    try {
      parsed = jsonDecode(jsonText);
    } catch (_) {
      throw BackupFormatException(
          'That file is not valid JSON, so it cannot be a Medstock backup.');
    }

    if (parsed is! Map<String, Object?>) {
      throw BackupFormatException('That file is not a Medstock backup.');
    }
    if (parsed['app'] != 'Medstock') {
      throw BackupFormatException(
          'That file was not exported by Medstock.');
    }

    final format = parsed['formatVersion'];
    if (format is! int) {
      throw BackupFormatException('The backup is missing its format version.');
    }
    if (format > formatVersion) {
      throw BackupFormatException(
          'This backup was made by a newer version of Medstock '
          '(format $format). Update the app, then import it again.');
    }

    final data = parsed['data'];
    if (data is! Map<String, Object?>) {
      throw BackupFormatException('The backup has no data section.');
    }

    final counts = <String, int>{};
    for (final table in _tables) {
      final rows = data[table];
      if (rows == null) {
        counts[table] = 0;
        continue;
      }
      if (rows is! List) {
        throw BackupFormatException('The "$table" section is malformed.');
      }
      counts[table] = rows.length;
    }

    if (counts.values.every((c) => c == 0)) {
      throw BackupFormatException('That backup is empty — nothing to import.');
    }

    return BackupPreview(
      exportedAt: DateTime.tryParse((parsed['exportedAt'] as String?) ?? ''),
      schemaVersion: parsed['schemaVersion'] as int?,
      counts: counts,
      document: parsed,
    );
  }

  /// Replaces everything in the book with the contents of [preview].
  ///
  /// Runs in one transaction: either the whole restore lands or the existing
  /// book is untouched. There is no partial state to clean up.
  Future<void> restore(BackupPreview preview) async {
    await primeColumnCache();
    final db = await _dbs.database;
    final data = preview.document['data'] as Map<String, Object?>;

    await db.transaction((txn) async {
      // Children first, so foreign keys stay satisfied while clearing.
      for (final table in _tables.reversed) {
        await txn.delete(table);
      }
      // Parents first when inserting.
      for (final table in _tables) {
        final rows = (data[table] as List?) ?? const [];
        for (final row in rows) {
          if (row is! Map) continue;
          await txn.insert(
            table,
            _sanitiseRow(table, row),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// Keeps only columns the current schema actually has, so a backup from an
  /// older or slightly different build still imports instead of throwing on an
  /// unknown column.
  Map<String, Object?> _sanitiseRow(String table, Map<Object?, Object?> row) {
    final allowed = _columns[table];
    final out = <String, Object?>{};
    row.forEach((key, value) {
      if (key is! String) return;
      if (allowed != null && !allowed.contains(key)) return;
      // JSON has no int/double distinction for whole numbers; sqflite is fine
      // with either, so values pass through as they are.
      out[key] = value;
    });
    return out;
  }

  /// Cached column names per table, read from the live schema.
  final Map<String, Set<String>> _columns = {};

  Future<void> primeColumnCache() async {
    if (_columns.isNotEmpty) return;
    final db = await _dbs.database;
    for (final table in _tables) {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      _columns[table] = cols.map((c) => c['name'] as String).toSet();
    }
    debugPrint('Medstock: backup column cache primed');
  }
}

/// What an import file holds, before anything is written.
class BackupPreview {
  BackupPreview({
    required this.exportedAt,
    required this.schemaVersion,
    required this.counts,
    required this.document,
  });

  final DateTime? exportedAt;
  final int? schemaVersion;
  final Map<String, int> counts;
  final Map<String, Object?> document;

  int get medicines => counts['medicines'] ?? 0;
  int get patients => counts['patients'] ?? 0;
  int get orders => counts['orders'] ?? 0;
  int get pharmacies => counts['pharmacies'] ?? 0;
}
