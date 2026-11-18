import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';

class SyncService {
  SyncService(this.client, this.localDb);

  final SupabaseClient client;
  final LocalDatabase localDb;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> sync(String userId) async {
    if (_running || client.auth.currentUser?.id != userId) return;
    _running = true;
    try {
      await _syncTransactions(userId);
      await _syncBudgets(userId);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncTransactions(String userId) async {
    final remoteRows = await client
        .from('budget_transactions')
        .select()
        .eq('user_id', userId);

    final pending = await localDb.getPendingTransactions(userId);
    final pendingIds = pending.map((row) => row['id'] as String).toSet();

    for (final remote in remoteRows) {
      final id = remote['id'] as String;
      if (pendingIds.contains(id)) continue;
      await localDb.upsertCloudTransaction({
        'id': id,
        'user_id': userId,
        'kind': remote['kind'],
        'amount': (remote['amount'] as num).toDouble(),
        'category': remote['category'],
        'transaction_date': remote['transaction_date'],
        'note': remote['note'] ?? '',
        'created_at': remote['created_at'],
        'updated_at': remote['updated_at'],
        'deleted_at': remote['deleted_at'],
      });
    }

    for (final row in pending) {
      await client.from('budget_transactions').upsert({
        'id': row['id'],
        'user_id': userId,
        'kind': row['kind'],
        'amount': row['amount'],
        'category': row['category'],
        'transaction_date': row['transaction_date'],
        'note': row['note'] ?? '',
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'deleted_at': row['deleted_at'],
      }, onConflict: 'id');
      await localDb.markTransactionSynced(row['id'] as String, userId);
    }
  }

  Future<void> _syncBudgets(String userId) async {
    final remoteRows = await client
        .from('monthly_budgets')
        .select()
        .eq('user_id', userId);

    final pending = await localDb.getPendingBudgets(userId);
    final pendingMonths = pending.map((row) => row['month'] as String).toSet();

    for (final remote in remoteRows) {
      final month = remote['month'] as String;
      if (pendingMonths.contains(month)) continue;
      await localDb.upsertCloudBudget({
        'user_id': userId,
        'month': month,
        'amount': (remote['amount'] as num).toDouble(),
        'updated_at': remote['updated_at'],
      });
    }

    for (final row in pending) {
      await client.from('monthly_budgets').upsert({
        'user_id': userId,
        'month': row['month'],
        'amount': row['amount'],
        'updated_at': row['updated_at'],
      }, onConflict: 'user_id,month');
      await localDb.markBudgetSynced(userId, row['month'] as String);
    }
  }
}
