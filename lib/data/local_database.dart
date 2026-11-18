import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final base = await getDatabasesPath();
    final db = await openDatabase(
      p.join(base, 'kwarta_budget.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions_local (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('expense','income')),
            amount REAL NOT NULL CHECK(amount > 0),
            category TEXT NOT NULL,
            transaction_date TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await db.execute('CREATE INDEX idx_tx_user_date ON transactions_local(user_id, transaction_date DESC)');
        await db.execute('CREATE INDEX idx_tx_user_sync ON transactions_local(user_id, sync_status)');
        await db.execute('''
          CREATE TABLE monthly_budgets_local (
            user_id TEXT NOT NULL,
            month TEXT NOT NULL,
            amount REAL NOT NULL CHECK(amount >= 0),
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            PRIMARY KEY(user_id, month)
          )
        ''');
      },
    );
    _database = db;
    return db;
  }

  Future<List<Map<String, dynamic>>> getTransactions(String userId) async {
    final db = await database;
    return db.query(
      'transactions_local',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'transaction_date DESC, created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingTransactions(String userId) async {
    final db = await database;
    return db.query(
      'transactions_local',
      where: 'user_id = ? AND sync_status = ?',
      whereArgs: [userId, 'pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> saveTransaction(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'transactions_local',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCloudTransaction(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'transactions_local',
      {...row, 'sync_status': 'synced'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markTransactionSynced(String id, String userId) async {
    final db = await database;
    await db.update(
      'transactions_local',
      {'sync_status': 'synced'},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getBudgets(String userId) async {
    final db = await database;
    return db.query(
      'monthly_budgets_local',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'month DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingBudgets(String userId) async {
    final db = await database;
    return db.query(
      'monthly_budgets_local',
      where: 'user_id = ? AND sync_status = ?',
      whereArgs: [userId, 'pending'],
      orderBy: 'month ASC',
    );
  }

  Future<void> saveBudget(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'monthly_budgets_local',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCloudBudget(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'monthly_budgets_local',
      {...row, 'sync_status': 'synced'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markBudgetSynced(String userId, String month) async {
    final db = await database;
    await db.update(
      'monthly_budgets_local',
      {'sync_status': 'synced'},
      where: 'user_id = ? AND month = ?',
      whereArgs: [userId, month],
    );
  }

  Future<int> pendingCount(String userId) async {
    final db = await database;
    final tx = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM transactions_local WHERE user_id = ? AND sync_status = ?',
      [userId, 'pending'],
    )) ?? 0;
    final budgets = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM monthly_budgets_local WHERE user_id = ? AND sync_status = ?',
      [userId, 'pending'],
    )) ?? 0;
    return tx + budgets;
  }
}
