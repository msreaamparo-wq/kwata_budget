import { useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';
import type { User } from '@supabase/supabase-js';
import { db, getUserBudgets, getUserTransactions, type BudgetRow, type TransactionRow } from './db';
import { supabase } from './supabase';

const EXPENSE_CATEGORIES = [
  'Pagkaon', 'Transportasyon', 'Kuryente/Tubig', 'Load/Internet',
  'Eskwela', 'Panimalay', 'Lingaw', 'Uban pa',
];
const INCOME_CATEGORIES = ['Sweldo', 'Negosyo', 'Regalo', 'Allowance', 'Uban pa'];
const money = new Intl.NumberFormat('en-PH', {
  style: 'currency',
  currency: 'PHP',
  minimumFractionDigits: 2,
});
const monthLabel = (date: Date) =>
  new Intl.DateTimeFormat('en-PH', { month: 'long', year: 'numeric' }).format(date);
const dateKey = (date: Date) =>
  date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' +
  String(date.getDate()).padStart(2, '0');
const monthKey = (date: Date) =>
  date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0');
const makeId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : String(Date.now()) + '-' + Math.random().toString(36).slice(2);

function readableError(error: unknown) {
  if (error instanceof Error) return error.message;
  return 'Something went wrong. Please try again.';
}

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [authMode, setAuthMode] = useState<'signin' | 'signup'>('signin');
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState('');
  const [notice, setNotice] = useState('');
  const [transactions, setTransactions] = useState<TransactionRow[]>([]);
  const [budgets, setBudgets] = useState<BudgetRow[]>([]);
  const [viewMonth, setViewMonth] = useState(() => new Date(new Date().getFullYear(), new Date().getMonth(), 1));
  const [online, setOnline] = useState(() => navigator.onLine);
  const [syncing, setSyncing] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [showBudget, setShowBudget] = useState(false);
  const [filter, setFilter] = useState<'all' | 'income' | 'expense'>('all');

  const currentMonthKey = monthKey(viewMonth);
  const currentRows = useMemo(
    () => transactions.filter((row) =>
      row.transaction_date.startsWith(currentMonthKey) && row.deleted_at === null
    ),
    [transactions, currentMonthKey],
  );
  const income = currentRows
    .filter((row) => row.kind === 'income')
    .reduce((sum, row) => sum + Number(row.amount), 0);
  const expenses = currentRows
    .filter((row) => row.kind === 'expense')
    .reduce((sum, row) => sum + Number(row.amount), 0);
  const balance = income - expenses;
  const budget = budgets.find((row) => row.month === currentMonthKey)?.amount ?? 0;
  const pendingCount =
    transactions.filter((row) => row.sync_status === 'pending').length +
    budgets.filter((row) => row.sync_status === 'pending').length;
  const expensesByCategory = useMemo(() => {
    const totals = new Map<string, number>();
    currentRows.filter((row) => row.kind === 'expense').forEach((row) => {
      totals.set(row.category, (totals.get(row.category) ?? 0) + Number(row.amount));
    });
    return Array.from(totals.entries()).sort((a, b) => b[1] - a[1]);
  }, [currentRows]);
  const visibleRows = currentRows
    .filter((row) => filter === 'all' || row.kind === filter)
    .sort((a, b) => b.transaction_date.localeCompare(a.transaction_date) || b.created_at.localeCompare(a.created_at));

  async function reloadLocal(userId: string) {
    const [localTransactions, localBudgets] = await Promise.all([
      getUserTransactions(userId),
      getUserBudgets(userId),
    ]);
    setTransactions(localTransactions);
    setBudgets(localBudgets);
  }

  async function syncNow(userId: string, quiet = false) {
    if (!navigator.onLine) {
      setOnline(false);
      if (!quiet) setNotice('Offline ka karon. Naa ra gihapon sa browser ang imong records.');
      return;
    }
    if (syncing) return;
    setSyncing(true);
    try {
      const [remoteTransactions, remoteBudgets] = await Promise.all([
        supabase.from('budget_transactions').select('*').eq('user_id', userId),
        supabase.from('monthly_budgets').select('*').eq('user_id', userId),
      ]);
      if (remoteTransactions.error) throw remoteTransactions.error;
      if (remoteBudgets.error) throw remoteBudgets.error;

      const localTransactions = await getUserTransactions(userId);
      const pendingTransactions = localTransactions.filter((row) => row.sync_status === 'pending');
      const pendingIds = new Set(pendingTransactions.map((row) => row.id));

      const cloudTransactions = (remoteTransactions.data ?? [])
        .filter((row) => !pendingIds.has(row.id))
        .map((row) => ({
          ...row,
          amount: Number(row.amount),
          note: row.note ?? '',
          sync_status: 'synced' as const,
        }));
      if (cloudTransactions.length) await db.transactions.bulkPut(cloudTransactions);

      for (const row of pendingTransactions) {
        const { error } = await supabase.from('budget_transactions').upsert({
          id: row.id,
          user_id: userId,
          kind: row.kind,
          amount: row.amount,
          category: row.category,
          transaction_date: row.transaction_date,
          note: row.note ?? '',
          created_at: row.created_at,
          updated_at: row.updated_at,
          deleted_at: row.deleted_at,
        }, { onConflict: 'id' });
        if (error) throw error;
        await db.transactions.update(row.id, { sync_status: 'synced' });
      }

      const localBudgets = await getUserBudgets(userId);
      const pendingBudgets = localBudgets.filter((row) => row.sync_status === 'pending');
      const pendingMonths = new Set(pendingBudgets.map((row) => row.month));
      const cloudBudgets = (remoteBudgets.data ?? [])
        .filter((row) => !pendingMonths.has(row.month))
        .map((row) => ({
          id: userId + '_' + row.month,
          user_id: userId,
          month: row.month,
          amount: Number(row.amount),
          updated_at: row.updated_at,
          sync_status: 'synced' as const,
        }));
      if (cloudBudgets.length) await db.budgets.bulkPut(cloudBudgets);

      for (const row of pendingBudgets) {
        const { error } = await supabase.from('monthly_budgets').upsert({
          user_id: userId,
          month: row.month,
          amount: row.amount,
          updated_at: row.updated_at,
        }, { onConflict: 'user_id,month' });
        if (error) throw error;
        await db.budgets.update(row.id, { sync_status: 'synced' });
      }

      await reloadLocal(userId);
      setOnline(true);
      if (!quiet) setNotice('Na-sync na ang imong records sa Supabase.');
    } catch (error) {
      await reloadLocal(userId);
      if (!quiet) setNotice('Naa ra sa device ang imong data. Wala pa na-sync: ' + readableError(error));
      console.warn('Kwarta sync is pending:', error);
    } finally {
      setSyncing(false);
    }
  }

  useEffect(() => {
    let active = true;
    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active) setUser(session?.user ?? null);
    });
    supabase.auth.getSession()
      .then(({ data, error }) => {
        if (error) throw error;
        if (active) setUser(data.session?.user ?? null);
      })
      .catch((error) => {
        if (active) setAuthError(readableError(error));
      })
      .finally(() => {
        if (active) setCheckingSession(false);
      });
    return () => {
      active = false;
      authListener.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!user) {
      setTransactions([]);
      setBudgets([]);
      return;
    }
    let active = true;
    const start = async () => {
      try {
        await reloadLocal(user.id);
        if (active && navigator.onLine) await syncNow(user.id, true);
      } catch (error) {
        console.warn('Could not load local Kwarta records:', error);
      }
    };
    void start();
    return () => { active = false; };
  }, [user?.id]);

  useEffect(() => {
    const handleOnline = () => {
      setOnline(true);
      if (user) void syncNow(user.id, true);
    };
    const handleOffline = () => {
      setOnline(false);
      setNotice('Offline mode. Magpabilin sa browser ang imong records.');
    };
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [user?.id]);

  async function handleAuth(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAuthError('');
    setAuthBusy(true);
    const form = new FormData(event.currentTarget);
    const email = String(form.get('email') ?? '').trim();
    const password = String(form.get('password') ?? '');
    try {
      if (authMode === 'signup') {
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        if (!data.session) {
          setNotice('Na-create na ang account. I-check ang imong email para sa confirmation, unya sign in.');
          setAuthMode('signin');
        } else {
          setUser(data.user);
        }
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        setUser(data.user);
      }
    } catch (error) {
      setAuthError(readableError(error));
    } finally {
      setAuthBusy(false);
    }
  }

  async function handleSignOut() {
    const accepted = window.confirm('Sign out sa Kwarta? Mabilin ang records niini nga browser.');
    if (!accepted) return;
    const { error } = await supabase.auth.signOut();
    if (error) setNotice('Na-sign out locally, pero wala makumpirma sa cloud: ' + error.message);
    setUser(null);
  }

  async function handleAddTransaction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return;
    const form = new FormData(event.currentTarget);
    const amount = Number(form.get('amount'));
    const kind = String(form.get('kind')) as 'income' | 'expense';
    const category = String(form.get('category') ?? '').trim();
    const transactionDate = String(form.get('transaction_date') ?? dateKey(new Date()));
    const note = String(form.get('note') ?? '').trim().slice(0, 80);
    if (!Number.isFinite(amount) || amount <= 0 || !category) {
      setNotice('Ibutang ang sakto nga amount ug category.');
      return;
    }
    const now = new Date().toISOString();
    const row: TransactionRow = {
      id: makeId(),
      user_id: user.id,
      kind,
      amount,
      category,
      transaction_date: transactionDate,
      note,
      created_at: now,
      updated_at: now,
      deleted_at: null,
      sync_status: 'pending',
    };
    await db.transactions.put(row);
    await reloadLocal(user.id);
    const chosenDate = new Date(transactionDate + 'T00:00:00');
    setViewMonth(new Date(chosenDate.getFullYear(), chosenDate.getMonth(), 1));
    setShowAdd(false);
    setNotice('Na-save locally. ' + (navigator.onLine ? 'I-sync sa cloud kung available.' : 'Offline mode — i-sync ra kung naay internet.'));
    if (navigator.onLine) void syncNow(user.id, true);
  }

  async function handleSaveBudget(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return;
    const form = new FormData(event.currentTarget);
    const amount = Number(form.get('budget'));
    if (!Number.isFinite(amount) || amount < 0) {
      setNotice('Ibutang ang valid nga budget amount.');
      return;
    }
    const now = new Date().toISOString();
    const row: BudgetRow = {
      id: user.id + '_' + currentMonthKey,
      user_id: user.id,
      month: currentMonthKey,
      amount,
      updated_at: now,
      sync_status: 'pending',
    };
    await db.budgets.put(row);
    await reloadLocal(user.id);
    setShowBudget(false);
    setNotice('Na-save ang monthly budget locally.');
    if (navigator.onLine) void syncNow(user.id, true);
  }

  async function handleDelete(row: TransactionRow) {
    if (!user || !window.confirm('Papason ang ' + row.category + ' nga record?')) return;
    const now = new Date().toISOString();
    await db.transactions.put({ ...row, deleted_at: now, updated_at: now, sync_status: 'pending' });
    await reloadLocal(user.id);
    setNotice('Na-delete ang record locally. I-sync kung naay internet.');
    if (navigator.onLine) void syncNow(user.id, true);
  }

  if (checkingSession) {
    return <main className="loading-screen"><div className="brand-mark">K</div><span>Opening Kwarta…</span></main>;
  }

  if (!user) {
    return (
      <main className="auth-screen">
        <section className="auth-showcase">
          <div className="brand-lockup"><div className="brand-mark">K</div><div><strong>kwarta.</strong><small>PERSONAL BUDGET TRACKER</small></div></div>
          <div className="auth-copy">
            <span className="eyebrow">YOUR MONEY, IN ORDER</span>
            <h1>Spend with purpose.<br /><em>Save with confidence.</em></h1>
            <p>Keep track of your income, expenses, and monthly budget — even when the internet is away.</p>
            <div className="showcase-points"><span>◈ Offline-first records</span><span>◈ Private cloud backup</span><span>◈ Simple money insights</span></div>
          </div>
          <div className="auth-foot">Made for everyday money decisions.</div>
        </section>
        <section className="auth-panel">
          <form className="auth-card" onSubmit={handleAuth}>
            <span className="eyebrow">{authMode === 'signin' ? 'WELCOME BACK' : 'GET STARTED'}</span>
            <h2>{authMode === 'signin' ? 'Sign in to Kwarta' : 'Create your account'}</h2>
            <p className="muted">{authMode === 'signin' ? 'Your money overview is waiting.' : 'Make one account to keep your records in sync.'}</p>
            <label>Email address<input name="email" type="email" placeholder="you@example.com" autoComplete="email" required /></label>
            <label>Password<input name="password" type="password" placeholder="At least 6 characters" minLength={6} autoComplete={authMode === 'signin' ? 'current-password' : 'new-password'} required /></label>
            {authError && <div className="form-error">{authError}</div>}
            <button className="primary-button full-button" type="submit" disabled={authBusy}>{authBusy ? 'Please wait…' : authMode === 'signin' ? 'Sign in' : 'Create account'} <span>↗</span></button>
            <p className="switch-auth">{authMode === 'signin' ? 'New to Kwarta?' : 'Already have an account?'} <button type="button" className="text-button" onClick={() => { setAuthMode(authMode === 'signin' ? 'signup' : 'signin'); setAuthError(''); }}>{authMode === 'signin' ? 'Create account' : 'Sign in'}</button></p>
            <div className="privacy-note">Your transactions are private to your account. First sign-in requires internet; after that, saved records remain available offline on this browser.</div>
          </form>
        </section>
        {notice && <div className="toast" role="status">{notice}<button onClick={() => setNotice('')} aria-label="Dismiss">×</button></div>}
      </main>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-lockup"><div className="brand-mark">K</div><div><strong>kwarta.</strong><small>PERSONAL FINANCE</small></div></div>
        <div className="side-label">WORKSPACE</div>
        <div className="side-link active"><span className="side-icon">▦</span> Overview</div>
        <div className="side-label side-label-bottom">ACCOUNT</div>
        <div className="account-card"><div className="avatar">{(user.email ?? 'K').slice(0, 1).toUpperCase()}</div><div className="account-text"><strong>{user.email}</strong><small>Personal account</small></div><button className="icon-button" onClick={handleSignOut} title="Sign out" aria-label="Sign out">↗</button></div>
        <div className="sidebar-note"><span className="note-spark">✳</span><strong>Small steps add up.</strong><p>A little awareness today can make a big difference tomorrow.</p></div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <div><span className="eyebrow">PERSONAL FINANCE / OVERVIEW</span><h1>Maayong adlaw!</h1><p>Here's how your money is doing.</p></div>
          <div className="top-actions">
            <div className={online ? 'connection-pill online' : 'connection-pill offline'}><span className="status-dot"></span>{syncing ? 'Syncing…' : online ? pendingCount ? pendingCount + ' pending' : 'Synced' : 'Offline'}</div>
            <button className="sync-button" onClick={() => void syncNow(user.id)} disabled={syncing || !online}>{syncing ? '↻ Syncing' : '↻ Sync now'}</button>
            <button className="avatar top-avatar" onClick={handleSignOut} title="Sign out">{(user.email ?? 'K').slice(0, 1).toUpperCase()}</button>
          </div>
        </header>

        <div className="month-toolbar">
          <div><span className="eyebrow">YOUR FINANCIAL SNAPSHOT</span><h2>{monthLabel(viewMonth)}</h2></div>
          <div className="month-controls"><button onClick={() => setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() - 1, 1))} aria-label="Previous month">‹</button><button onClick={() => setViewMonth(new Date(new Date().getFullYear(), new Date().getMonth(), 1))}>This month</button><button onClick={() => setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 1))} aria-label="Next month">›</button></div>
        </div>

        <section className="summary-grid">
          <article className="summary-card balance-card"><div className="summary-top"><span>Available balance</span><span className="summary-icon">₱</span></div><strong>{money.format(balance)}</strong><small>Income minus expenses this month</small><div className="balance-decoration"></div></article>
          <article className="summary-card"><div className="summary-top"><span>Total income</span><span className="summary-icon income-icon">↗</span></div><strong className="income-text">{money.format(income)}</strong><small>Money received this month</small></article>
          <article className="summary-card"><div className="summary-top"><span>Total expenses</span><span className="summary-icon expense-icon">↘</span></div><strong className="expense-text">{money.format(expenses)}</strong><small>Money spent this month</small></article>
        </section>

        <section className="content-grid">
          <div className="main-column">
            <article className="panel budget-panel">
              <div className="panel-heading"><div><span className="eyebrow">MONTHLY PLAN</span><h3>Budget progress</h3></div><button className="outline-button" onClick={() => setShowBudget(true)}>Edit budget</button></div>
              <div className="budget-amount-row"><strong>{money.format(expenses)}</strong><span>{budget > 0 ? 'of ' + money.format(budget) : 'spent this month'}</span></div>
              <div className="progress-track"><div className="progress-fill" style={{ width: (budget > 0 ? Math.min(100, (expenses / budget) * 100) : 0) + '%' }}></div></div>
              <div className="budget-foot"><span>{budget > 0 ? (expenses > budget ? money.format(expenses - budget) + ' over budget' : money.format(budget - expenses) + ' remaining') : 'Set a monthly limit to track your spending'}</span><span>{budget > 0 ? Math.round((expenses / budget) * 100) + '%' : '—'}</span></div>
            </article>

            <article className="panel spending-panel">
              <div className="panel-heading"><div><span className="eyebrow">WHERE IT GOES</span><h3>Spending by category</h3></div><span className="subtle-tag">{expensesByCategory.length} categories</span></div>
              {expensesByCategory.length === 0 ? <div className="empty-state"><span>◌</span><strong>No expenses yet</strong><p>Your spending categories will appear here when you add a record.</p></div> :
                <div className="category-list">{expensesByCategory.map(([category, amount]) => (
                  <div className="category-row" key={category}><div className="category-top"><strong>{category}</strong><span>{money.format(amount)}</span></div><div className="category-track"><div style={{ width: (expenses ? Math.max(3, amount / expenses * 100) : 0) + '%' }}></div></div></div>
                ))}</div>}
            </article>
          </div>

          <aside className="side-column">
            <article className="quick-card"><div className="quick-symbol">＋</div><span className="eyebrow">QUICK ACTION</span><h3>Record your money</h3><p>Add income or expenses as they happen. Your entry is saved on this device first.</p><button className="primary-button full-button" onClick={() => setShowAdd(true)}>＋ Add a record</button></article>
            <article className="tip-card"><span className="tip-star">✳</span><span className="eyebrow">A LITTLE REMINDER</span><h3>Know where it goes.</h3><p>Tracking small expenses can help you make room for the things that matter.</p></article>
            <div className="sync-caption"><span className={online ? 'tiny-dot' : 'tiny-dot is-offline'}></span>{online ? syncing ? 'Syncing your cloud backup…' : pendingCount ? pendingCount + ' change(s) waiting to sync' : 'Your records are backed up' : 'Offline — changes stay on this browser'}</div>
          </aside>
        </section>

        <section className="panel transactions-panel">
          <div className="panel-heading transaction-heading"><div><span className="eyebrow">ACTIVITY</span><h3>Recent records <span className="count-badge">{currentRows.length}</span></h3></div><div className="filter-tabs"><button className={filter === 'all' ? 'selected' : ''} onClick={() => setFilter('all')}>All</button><button className={filter === 'income' ? 'selected' : ''} onClick={() => setFilter('income')}>Income</button><button className={filter === 'expense' ? 'selected' : ''} onClick={() => setFilter('expense')}>Expense</button></div></div>
          {visibleRows.length === 0 ? <div className="empty-state transaction-empty"><span>▤</span><strong>No records for this month</strong><p>Tap “Add a record” to start tracking your money.</p></div> :
            <div className="table-wrap"><table><thead><tr><th>DETAILS</th><th>DATE</th><th>CATEGORY</th><th className="amount-column">AMOUNT</th><th></th></tr></thead><tbody>
              {visibleRows.map((row) => <tr key={row.id}><td><div className="record-title"><span className={row.kind === 'income' ? 'record-symbol income-symbol' : 'record-symbol expense-symbol'}>{row.kind === 'income' ? '↗' : '↘'}</span><div><strong>{row.note || row.category}</strong><small>{row.kind === 'income' ? 'Income' : 'Expense'}</small></div></div></td><td>{new Intl.DateTimeFormat('en-PH', { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(row.transaction_date + 'T00:00:00'))}</td><td><span className="category-chip">{row.category}</span></td><td className={'amount-column ' + (row.kind === 'income' ? 'income-text' : 'expense-text')}>{row.kind === 'income' ? '+' : '−'}{money.format(Number(row.amount))}</td><td><button className="delete-button" title="Delete record" aria-label="Delete record" onClick={() => void handleDelete(row)}>×</button></td></tr>)}
            </tbody></table></div>}
        </section>
        <footer className="page-footer"><span>kwarta. <b>·</b> Your money, in order.</span><span>Saved locally first · Synced with Supabase when online</span></footer>
      </main>

      {showAdd && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowAdd(false); }}><form className="modal-card" onSubmit={handleAddTransaction}><div className="modal-heading"><div><span className="eyebrow">NEW ENTRY</span><h3>Add a record</h3></div><button type="button" className="close-button" onClick={() => setShowAdd(false)}>×</button></div><label>Type<select name="kind" defaultValue="expense" onChange={(event) => { const target = event.currentTarget.form?.elements.namedItem('category') as HTMLSelectElement | null; if (target) target.innerHTML = (event.target.value === 'income' ? INCOME_CATEGORIES : EXPENSE_CATEGORIES).map((item) => '<option>' + item + '</option>').join(''); }}><option value="expense">Expense</option><option value="income">Income</option></select></label><label>Amount (₱)<input name="amount" type="number" min="0.01" step="0.01" placeholder="0.00" required autoFocus /></label><label>Category<select name="category">{EXPENSE_CATEGORIES.map((item) => <option key={item}>{item}</option>)}</select></label><label>Date<input name="transaction_date" type="date" defaultValue={dateKey(new Date())} required /></label><label>Note <span className="optional-label">optional</span><input name="note" type="text" maxLength={80} placeholder="What was this for?" /></label><div className="modal-actions"><button type="button" className="outline-button" onClick={() => setShowAdd(false)}>Cancel</button><button type="submit" className="primary-button">Save record</button></div><p className="modal-hint">This record is stored on this browser first, then synced when you're online.</p></form></div>}

      {showBudget && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowBudget(false); }}><form className="modal-card" onSubmit={handleSaveBudget}><div className="modal-heading"><div><span className="eyebrow">MONTHLY PLAN</span><h3>Set your budget</h3></div><button type="button" className="close-button" onClick={() => setShowBudget(false)}>×</button></div><p className="muted">Set a spending limit for {monthLabel(viewMonth)}.</p><label>Monthly limit (₱)<input name="budget" type="number" min="0" step="0.01" defaultValue={budget || ''} placeholder="e.g. 10000" required autoFocus /></label><div className="modal-actions"><button type="button" className="outline-button" onClick={() => setShowBudget(false)}>Cancel</button><button type="submit" className="primary-button">Save budget</button></div><p className="modal-hint">Your budget is also saved locally first.</p></form></div>}

      {notice && <div className="toast" role="status">{notice}<button onClick={() => setNotice('')} aria-label="Dismiss">×</button></div>}
    </div>
  );
}