import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('naggly_afis.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Table principale de l'Index Inversé Géométrique
    // signature = "L1_L2_L3" (Les longueurs quantifiées du triangle de Delaunay)
    // animal_id = L'ID de la vache
    await db.execute('''
      CREATE TABLE inverted_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        signature TEXT NOT NULL,
        animal_id TEXT NOT NULL
      )
    ''');

    // Index B-Tree ultra rapide sur les signatures (recherche en O(log n))
    await db.execute('CREATE INDEX idx_signature ON inverted_index (signature)');

    // Table des animaux enregistrés (pour le comptage et la gestion)
    await db.execute('''
      CREATE TABLE animals (
        id TEXT PRIMARY KEY,
        registered_at TEXT NOT NULL,
        signature_count INTEGER NOT NULL
      )
    ''');
  }

  /// Nombre total de vaches enregistrées dans le téléphone
  Future<int> getAnimalCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM animals');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Enregistrement d'une nouvelle vache (permanent dans le stockage du téléphone)
  Future<void> registerAnimal(String animalId, List<String> signatures) async {
    final db = await instance.database;

    // Insertion de l'animal dans le registre
    await db.insert('animals', {
      'id': animalId,
      'registered_at': DateTime.now().toIso8601String(),
      'signature_count': signatures.length,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Insertion en batch de toutes les signatures géométriques
    Batch batch = db.batch();
    for (String sig in signatures) {
      batch.insert('inverted_index', {
        'signature': sig,
        'animal_id': animalId,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Identification (1:N) instantanée grâce à l'index B-Tree de SQLite
  Future<Map<String, int>> identify(List<String> querySignatures) async {
    final db = await instance.database;
    if (querySignatures.isEmpty) return {};

    // On regroupe les signatures pour faire un seul IN query optimisé
    // SQLite gère jusqu'à 999 variables — on découpe si nécessaire
    Map<String, int> allVotes = {};

    for (int i = 0; i < querySignatures.length; i += 500) {
      final chunk = querySignatures.sublist(
        i, i + 500 > querySignatures.length ? querySignatures.length : i + 500,
      );
      String placeholders = List.filled(chunk.length, '?').join(',');

      final result = await db.rawQuery('''
        SELECT animal_id, COUNT(*) as votes
        FROM inverted_index
        WHERE signature IN ($placeholders)
        GROUP BY animal_id
        ORDER BY votes DESC
        LIMIT 10
      ''', chunk);

      for (var row in result) {
        final id = row['animal_id'] as String;
        final v = row['votes'] as int;
        allVotes[id] = (allVotes[id] ?? 0) + v;
      }
    }

    return allVotes;
  }
}
