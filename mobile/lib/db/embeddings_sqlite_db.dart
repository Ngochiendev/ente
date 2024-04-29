import "dart:io";
import "dart:typed_data";

import "package:path/path.dart";
import 'package:path_provider/path_provider.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/embedding_updated_event.dart";
import "package:photos/models/embedding.dart";
import "package:sqlite_async/sqlite_async.dart";

class EmbeddingsDB {
  EmbeddingsDB._privateConstructor();

  static final EmbeddingsDB instance = EmbeddingsDB._privateConstructor();

  static const databaseName = "ente.embeddings.db";
  static const tableName = "embeddings";
  static const columnFileID = "file_id";
  static const columnModel = "model";
  static const columnEmbedding = "embedding";
  static const columnUpdationTime = "updation_time";

  static Future<SqliteDatabase>? _dbFuture;

  Future<SqliteDatabase> get _database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<SqliteDatabase> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, databaseName);
    final migrations = SqliteMigrations()
      ..add(
        SqliteMigration(
          1,
          (tx) async {
            await tx.execute(
              'CREATE TABLE $tableName ($columnFileID INTEGER NOT NULL, $columnModel TEXT NOT NULL, $columnEmbedding BLOB NOT NULL, $columnUpdationTime INTEGER, UNIQUE ($columnFileID, $columnModel))',
            );
          },
        ),
      );
    final database = SqliteDatabase(path: path);
    await migrations.migrate(database);
    return database;
  }

  Future<void> clearTable() async {
    final db = await _database;
    await db.execute('DELETE * FROM $tableName');
  }

  Future<List<Embedding>> getAll(Model model) async {
    final db = await _database;
    final results = await db.getAll('SELECT * FROM $tableName');
    return _convertToEmbeddings(results);
  }

  Future<void> put(Embedding embedding) async {
    final db = await _database;
    await db.execute(
      'INSERT OR REPLACE INTO $tableName ($columnFileID, $columnModel, $columnEmbedding, $columnUpdationTime) VALUES (?, ?, ?, ?)',
      _getRowFromEmbedding(embedding),
    );
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  Future<void> putMany(List<Embedding> embeddings) async {
    final db = await _database;
    final inputs = embeddings.map((e) => _getRowFromEmbedding(e)).toList();
    await db.executeBatch(
      'INSERT OR REPLACE INTO $tableName ($columnFileID, $columnModel, $columnEmbedding, $columnUpdationTime) values(?, ?, ?, ?)',
      inputs,
    );
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  Future<List<Embedding>> getUnsyncedEmbeddings() async {
    final db = await _database;
    final results = await db.getAll(
      'SELECT * FROM $tableName WHERE $columnUpdationTime IS NULL',
    );
    return _convertToEmbeddings(results);
  }

  Future<void> deleteEmbeddings(List<int> fileIDs) async {
    final db = await _database;
    await db.execute(
      'DELETE FROM $tableName WHERE $columnFileID IN (${fileIDs.join(", ")})',
    );
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  Future<void> deleteAllForModel(Model model) async {
    final db = await _database;
    await db.execute(
      'DELETE FROM $tableName WHERE $columnModel = ?',
      [serialize(model)],
    );
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  List<Embedding> _convertToEmbeddings(List<Map<String, dynamic>> results) {
    final List<Embedding> embeddings = [];
    for (final result in results) {
      embeddings.add(_getEmbeddingFromRow(result));
    }
    return embeddings;
  }

  Embedding _getEmbeddingFromRow(Map<String, dynamic> row) {
    final fileID = row[columnFileID];
    final model = deserialize(row[columnModel]);
    final bytes = row[columnEmbedding] as Uint8List;
    final list = Float32List.view(bytes.buffer);
    return Embedding(fileID: fileID, model: model, embedding: list);
  }

  List<Object?> _getRowFromEmbedding(Embedding embedding) {
    return [
      embedding.fileID,
      serialize(embedding.model),
      Float32List.fromList(embedding.embedding).buffer.asUint8List(),
      embedding.updationTime,
    ];
  }
}
