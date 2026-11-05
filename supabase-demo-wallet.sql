-- Run this once in Supabase Dashboard > SQL Editor for shared demo balances.
create table if not exists public.demo_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(12, 2) not null default 0.00 check (balance >= 0),
  created_at timestamptz not null default now()
);

alter table public.demo_wallets alter column balance set default 0.00;

create table if not exists public.demo_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  transfer_id uuid not null,
  title text not null,
  amount numeric(12, 2) not null,
  created_at timestamptz not null default now()
);

create index if not exists demo_transactions_user_created_idx
  on public.demo_transactions (user_id, created_at desc);

alter table public.demo_wallets enable row level security;
alter table public.demo_transactions enable row level security;

drop policy if exists "Users can read their own demo wallet" on public.demo_wallets;
create policy "Users can read their own demo wallet"
  on public.demo_wallets for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can read their own demo transactions" on public.demo_transactions;
create policy "Users can read their own demo transactions"
  on public.demo_transactions for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.ensure_demo_wallet()
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_balance numeric(12, 2);
begin
  if current_user_id is null then
    raise exception 'Sign in to use the demo wallet.';
  end if;

  insert into public.demo_wallets (user_id, balance)
  values (current_user_id, 0.00)
  on conflict (user_id) do nothing;

  select balance into current_balance
  from public.demo_wallets
  where user_id = current_user_id;

  return current_balance;
end;
$$;

create or replace function public.transfer_demo_funds(
  p_recipient_email text,
  p_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_id uuid := auth.uid();
  recipient_id uuid;
  sender_email text;
  recipient_email text;
  sender_balance numeric(12, 2);
  recipient_balance numeric(12, 2);
  transfer_key uuid := gen_random_uuid();
  transfer_amount numeric(12, 2) := round(p_amount, 2);
begin
  if sender_id is null then
    raise exception 'Sign in before sending demo funds.';
  end if;
  if transfer_amount is null or transfer_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  select email into sender_email from auth.users where id = sender_id;
  select id, email into recipient_id, recipient_email
  from auth.users
  where lower(email) = lower(trim(p_recipient_email))
  limit 1;

  if recipient_id is null then
    raise exception 'No registered user was found with that email.';
  end if;
  if recipient_id = sender_id then
    raise exception 'You cannot send demo funds to yourself.';
  end if;

  -- Create both demo wallets once, then lock them in a stable order.
  if sender_id < recipient_id then
    insert into public.demo_wallets (user_id, balance) values (sender_id, 0.00) on conflict do nothing;
    insert into public.demo_wallets (user_id, balance) values (recipient_id, 0.00) on conflict do nothing;
  else
    insert into public.demo_wallets (user_id, balance) values (recipient_id, 0.00) on conflict do nothing;
    insert into public.demo_wallets (user_id, balance) values (sender_id, 0.00) on conflict do nothing;
  end if;

  perform user_id from public.demo_wallets
  where user_id in (sender_id, recipient_id)
  order by user_id
  for update;

  select balance into sender_balance from public.demo_wallets where user_id = sender_id;
  select balance into recipient_balance from public.demo_wallets where user_id = recipient_id;

  if sender_balance < transfer_amount then
    raise exception 'Insufficient demo balance. Available: $%.', sender_balance;
  end if;

  update public.demo_wallets set balance = balance - transfer_amount where user_id = sender_id returning balance into sender_balance;
  update public.demo_wallets set balance = balance + transfer_amount where user_id = recipient_id returning balance into recipient_balance;

  insert into public.demo_transactions (user_id, transfer_id, title, amount)
  values
    (sender_id, transfer_key, 'Sent to ' || recipient_email, -transfer_amount),
    (recipient_id, transfer_key, 'Received from ' || sender_email, transfer_amount);

  return jsonb_build_object('balance', sender_balance, 'recipient_balance', recipient_balance);
end;
$$;

create or replace function public.withdraw_demo_funds(
  p_amount numeric,
  p_method text
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_balance numeric(12, 2);
  withdrawal_amount numeric(12, 2) := round(p_amount, 2);
begin
  if current_user_id is null then
    raise exception 'Sign in before withdrawing demo funds.';
  end if;
  if withdrawal_amount is null or withdrawal_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if p_method not in ('bank', 'paypal', 'crypto') then
    raise exception 'Choose a valid demo withdrawal method.';
  end if;

  perform public.ensure_demo_wallet();
  select balance into current_balance from public.demo_wallets where user_id = current_user_id for update;
  if current_balance < withdrawal_amount then
    raise exception 'Insufficient demo balance. Available: $%.', current_balance;
  end if;

  update public.demo_wallets
  set balance = balance - withdrawal_amount
  where user_id = current_user_id
  returning balance into current_balance;

  insert into public.demo_transactions (user_id, transfer_id, title, amount)
  values (current_user_id, gen_random_uuid(), 'Withdrawal (' || p_method || ')', -withdrawal_amount);

  return current_balance;
end;
$$;

revoke all on function public.ensure_demo_wallet() from public, anon;
revoke all on function public.transfer_demo_funds(text, numeric) from public, anon;
revoke all on function public.withdraw_demo_funds(numeric, text) from public, anon;
grant execute on function public.ensure_demo_wallet() to authenticated;
grant execute on function public.transfer_demo_funds(text, numeric) to authenticated;
grant execute on function public.withdraw_demo_funds(numeric, text) to authenticated;

grant select on public.demo_wallets, public.demo_transactions to authenticated;
