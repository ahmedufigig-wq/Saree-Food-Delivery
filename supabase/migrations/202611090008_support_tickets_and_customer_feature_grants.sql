create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null check (char_length(trim(subject)) between 3 and 120),
  message text not null check (char_length(trim(message)) between 5 and 3000),
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  admin_reply text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_user_created_idx on public.support_tickets(user_id, created_at desc);
create index if not exists support_tickets_status_created_idx on public.support_tickets(status, created_at desc);
alter table public.support_tickets enable row level security;
drop policy if exists "customers read own support tickets" on public.support_tickets;
create policy "customers read own support tickets" on public.support_tickets
for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "customers create own support tickets" on public.support_tickets;
create policy "customers create own support tickets" on public.support_tickets
for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "admins manage support tickets" on public.support_tickets;
create policy "admins manage support tickets" on public.support_tickets
for update to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert on public.support_tickets to authenticated;
grant update on public.support_tickets to authenticated;
grant select, insert, update, delete on public.favorites to authenticated;
grant select, insert, update on public.reviews to authenticated;
grant select, update on public.notifications to authenticated;
