-- Kwarta Budget Tracker schema for the existing Supabase project.
-- Run this in Supabase Dashboard > SQL Editor if setting up a fresh project.

create table if not exists public.budget_transactions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('expense', 'income')),
  amount numeric(14, 2) not null check (amount > 0),
  category text not null check (char_length(category) between 1 and 60),
  transaction_date date not null,
  note text not null default '' check (char_length(note) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists budget_transactions_user_date_idx
  on public.budget_transactions (user_id, transaction_date desc);

alter table public.budget_transactions enable row level security;

drop policy if exists "Users can read their own budget transactions" on public.budget_transactions;
create policy "Users can read their own budget transactions"
  on public.budget_transactions for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own budget transactions" on public.budget_transactions;
create policy "Users can insert their own budget transactions"
  on public.budget_transactions for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own budget transactions" on public.budget_transactions;
create policy "Users can update their own budget transactions"
  on public.budget_transactions for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update on public.budget_transactions to authenticated;

create table if not exists public.monthly_budgets (
  user_id uuid not null references auth.users(id) on delete cascade,
  month text not null check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  amount numeric(14, 2) not null check (amount >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);

alter table public.monthly_budgets enable row level security;

drop policy if exists "Users can read their own monthly budgets" on public.monthly_budgets;
create policy "Users can read their own monthly budgets"
  on public.monthly_budgets for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own monthly budgets" on public.monthly_budgets;
create policy "Users can insert their own monthly budgets"
  on public.monthly_budgets for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own monthly budgets" on public.monthly_budgets;
create policy "Users can update their own monthly budgets"
  on public.monthly_budgets for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update on public.monthly_budgets to authenticated;
