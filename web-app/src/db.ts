import Dexie, { type Table } from 'dexie';

export type TransactionRow = {
  id: string;
  user_id: string;
  kind: 'income' | 'expense';
  amount: number;
  category: string;
  transaction_date: string;
  note: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  sync_status: 'pending' | 'synced';
};

export type BudgetRow = {
  id: string;
  user_id: string;
  month: string;
  amount: number;
  updated_at: string;
  sync_status: 'pending' | 'synced';
};

class KwartaDatabase extends Dexie {
  transactions!: Table<TransactionRow, string>;
  budgets!: Table<BudgetRow, string>;

  constructor() {
    super('kwarta_budget_web');
    this.version(1).stores({
      transactions: 'id, user_id, transaction_date, sync_status',
      budgets: 'id, user_id, month, sync_status',
    });
  }
}

export const db = new KwartaDatabase();

export async function getUserTransactions(userId: string) {
  return db.transactions.where('user_id').equals(userId).toArray();
}

export async function getUserBudgets(userId: string) {
  return db.budgets.where('user_id').equals(userId).toArray();
}