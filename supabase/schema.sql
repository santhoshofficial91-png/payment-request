create sequence if not exists public.pr_seq;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  name text not null,
  email text default '',
  phone text default '',
  role text not null check (role in ('admin','manager','executive')),
  manager_name text default '',
  created_at timestamptz not null default now()
);

create table public.payments (
  n bigint primary key default nextval('public.pr_seq'),
  id text generated always as ('PR-' || lpad(n::text, 3, '0')) stored,
  requester_id uuid references public.profiles(id) on delete set null,
  req_name text not null default '',
  enq text default '', req_date text default '', po text default '', supplier text default '',
  customer text default '', purpose text default '', delivery_date text default '', lead_time text default '',
  stock_status text default '', stock_location text default '',
  amount numeric not null default 0,
  status text not null default 'Pending',
  requester_remark text default '', accounts_remark text default '',
  pr_status text not null default 'Request Not Sent',
  paid_at bigint not null default 0,
  returned boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.po (
  n bigint generated always as identity primary key,
  enq text default '', po_date text default '', supplier text default '',
  po_num text not null, po_value numeric not null default 0, paid numeric not null default 0,
  balance numeric not null default 0, requester text default '',
  created_at timestamptz not null default now()
);
create unique index po_num_unique on public.po (lower(btrim(po_num)));

create or replace function public.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid()
$$;
revoke execute on function public.my_role() from public, anon;
grant execute on function public.my_role() to authenticated;

create or replace function public.payments_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.my_role() = 'executive' then
    if tg_op = 'INSERT' then
      new.status := 'Pending'; new.pr_status := 'Request Not Sent'; new.paid_at := 0; new.returned := false;
      new.accounts_remark := ''; new.requester_id := auth.uid();
    else
      new.status := old.status; new.accounts_remark := old.accounts_remark; new.paid_at := old.paid_at;
      new.requester_id := old.requester_id; new.req_name := old.req_name; new.req_date := old.req_date;
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.payments_guard() from public, anon, authenticated;
create trigger payments_guard_trg before insert or update on public.payments
  for each row execute function public.payments_guard();

alter table public.profiles enable row level security;
alter table public.payments enable row level security;
alter table public.po enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (true);

create policy pay_select on public.payments for select to authenticated using (
  public.my_role() = 'admin'
  or (public.my_role() = 'manager' and pr_status = 'Request Sent')
  or (public.my_role() = 'executive' and requester_id = (select auth.uid()))
);
create policy pay_insert on public.payments for insert to authenticated with check (
  public.my_role() in ('admin','manager','executive') and requester_id = (select auth.uid())
);
create policy pay_update_staff on public.payments for update to authenticated
  using (public.my_role() = 'admin' or (public.my_role() = 'manager' and pr_status = 'Request Sent'))
  with check (public.my_role() in ('admin','manager') and (public.my_role() = 'admin' or pr_status = 'Request Sent'));
create policy pay_update_exe on public.payments for update to authenticated
  using (public.my_role() = 'executive' and requester_id = (select auth.uid()) and pr_status <> 'Request Sent')
  with check (public.my_role() = 'executive' and requester_id = (select auth.uid()));

create policy po_read on public.po for select to authenticated using (true);
create policy po_ins on public.po for insert to authenticated with check (public.my_role() = 'admin');
create policy po_upd on public.po for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
create policy po_del on public.po for delete to authenticated using (public.my_role() = 'admin');

alter table public.payments replica identity full;
alter table public.po replica identity full;
alter table public.profiles replica identity full;
alter publication supabase_realtime add table public.payments, public.po, public.profiles;

-- Manager team scope + revoke (applied as migration manager_team_scope_and_revoke)
-- is_my_team(), pay_select / pay_update_staff / pay_insert policies and revoke_request() were updated:
-- managers see only their own team's requests that are sent and not Paid, and revoke them through revoke_request().

-- Expense requests (applied as migration expense_requests):
-- table public.expenses (id EX-###), expenses_guard trigger (only the admin may change status / accounts remark),
-- RLS: admin sees all; users see their own; managers also see their team's sent, not-Paid requests;
-- revoke_expense() lets a manager send a team request back.

-- Later migration: department / enquiry / debit-to
-- alter table public.profiles add column department text not null default '';
-- alter table public.expenses add column enq text not null default '', add column debit_to text not null default '', add column department text not null default '';

-- Later migration: supplier cut-off (2 PM IST): pr_cutoff_over(), executive send blocked in payments_guard,
-- manager can see/send unsent team requests after cut-off via mgr_send_requests(bigint[]).

-- Later migration: managers raise supplier requests (pay_insert/pay_select/pay_update_mgr_own, payments_guard),
-- managers can forward unsent team requests at any time (mgr_send_requests).
-- Later migration: expenses_guard no longer forces req_date on update (request date is entered manually).
-- Later migration: profile_secrets (admin-readable passwords); HR department.
-- Later migration: is_sub_admin() + po insert/update policies allow Sub Admin (executive with department 'Sub Admin').
-- Later migration: pr_status 'With Manager' (executive send after cut-off goes to manager; Sample bypasses cut-off); policies/guard/mgr_send_requests updated.

-- Later migration: sent_at (bigint ms) on payments & expenses, stamped by trigger zz_stamp_sent (function stamp_sent_at)
-- when pr_status first becomes 'Request Sent' / 'With Manager'; reset to 0 when the request goes back to 'Request Not Sent'.
