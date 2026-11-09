-- Cities, self-service role requests, administrator approval and an auditable wallet ledger.
-- Applied to the connected Supabase project; all wallet balances are derived from immutable entries.
begin;
create table if not exists public.cities(id uuid primary key default gen_random_uuid(),name text not null unique,country text not null default 'اليمن',is_active boolean not null default true,created_at timestamptz not null default now());
insert into public.cities(name,country,is_active) values('رداع','اليمن',true) on conflict(name) do update set is_active=true;
alter table public.restaurants add column if not exists city_id uuid references public.cities(id);
update public.restaurants r set city_id=c.id from public.cities c where r.city='رداع' and r.city_id is null;
alter table public.profiles add column if not exists approval_status text not null default 'approved',add column if not exists approval_requested_at timestamptz,add column if not exists approved_at timestamptz,add column if not exists approval_note text;
alter table public.profiles drop constraint if exists profiles_approval_status_check;
alter table public.profiles add constraint profiles_approval_status_check check(approval_status in('approved','pending','rejected'));
update public.profiles set approved_at=coalesce(approved_at,created_at) where role='customer' and approval_status='approved';
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare requested_role text:=coalesce(new.raw_user_meta_data->>'requested_role','customer');
begin
 if requested_role not in('customer','courier','restaurant_owner') then requested_role:='customer'; end if;
 insert into public.profiles(id,full_name,phone,role,approval_status,approval_requested_at,approved_at)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),nullif(new.raw_user_meta_data->>'phone',''),requested_role::public.app_role,
 case when requested_role='customer' then 'approved' else 'pending' end,
 case when requested_role='customer' then null else now() end,
 case when requested_role='customer' then now() else null end);
 return new;
end $$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
grant execute on function public.handle_new_user() to service_role;
create or replace function public.protect_profile_privileges() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if (new.role is distinct from old.role or new.approval_status is distinct from old.approval_status or new.approved_at is distinct from old.approved_at) and not public.is_admin() then raise exception 'تغيير الدور أو الاعتماد متاح للمدير فقط'; end if; return new;
end $$;
drop trigger if exists protect_profile_privileges on public.profiles;
create trigger protect_profile_privileges before update on public.profiles for each row execute function public.protect_profile_privileges();
revoke all on function public.protect_profile_privileges() from public,anon,authenticated;
create or replace function public.admin_review_user(p_user_id uuid,p_decision text,p_note text default null) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare target_role public.app_role;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'متاح للمدير فقط'; end if;
 if p_decision not in('approved','rejected') then raise exception 'قرار اعتماد غير صالح'; end if;
 select role into target_role from public.profiles where id=p_user_id for update;
 if not found then raise exception 'الحساب غير موجود'; end if;
 if target_role in('customer','admin') then raise exception 'هذا الحساب لا يحتاج اعتماداً'; end if;
 update public.profiles set approval_status=p_decision,approved_at=case when p_decision='approved' then now() else null end,approval_note=nullif(trim(coalesce(p_note,'')),'') where id=p_user_id;
end $$;
revoke all on function public.admin_review_user(uuid,text,text) from public,anon;
grant execute on function public.admin_review_user(uuid,text,text) to authenticated;
create table if not exists public.wallet_transactions(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete restrict,amount_yer bigint not null check(amount_yer<>0),kind text not null check(kind in('admin_credit','admin_debit','refund','adjustment')),reference text,note text not null default '',created_by uuid references public.profiles(id),created_at timestamptz not null default now());
create index if not exists wallet_transactions_user_created_idx on public.wallet_transactions(user_id,created_at desc);
alter table public.wallet_transactions enable row level security;
drop policy if exists wallet_transactions_read_own_or_admin on public.wallet_transactions;
create policy wallet_transactions_read_own_or_admin on public.wallet_transactions for select to authenticated using(user_id=auth.uid() or public.is_admin());
create or replace view public.wallet_balances with(security_invoker=true) as select p.id as user_id,coalesce(sum(w.amount_yer),0)::bigint as balance_yer from public.profiles p left join public.wallet_transactions w on w.user_id=p.id group by p.id;
grant select on public.wallet_balances to authenticated;
create or replace function public.admin_wallet_adjust(p_user_id uuid,p_amount_yer bigint,p_kind text,p_note text default '') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare new_id uuid;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'متاح للمدير فقط'; end if;
 if p_amount_yer=0 or abs(p_amount_yer)>100000000 then raise exception 'المبلغ غير صالح'; end if;
 if p_kind not in('admin_credit','admin_debit','refund','adjustment') then raise exception 'نوع الحركة غير صالح'; end if;
 if p_kind='admin_credit' and p_amount_yer<0 then raise exception 'قيمة الإيداع يجب أن تكون موجبة'; end if;
 if p_kind='admin_debit' and p_amount_yer>0 then raise exception 'قيمة الخصم يجب أن تكون سالبة'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'الحساب غير موجود'; end if;
 if (select coalesce(sum(amount_yer),0) from public.wallet_transactions where user_id=p_user_id)+p_amount_yer<0 then raise exception 'الرصيد غير كافٍ لإجراء الخصم'; end if;
 insert into public.wallet_transactions(user_id,amount_yer,kind,note,created_by) values(p_user_id,p_amount_yer,p_kind,coalesce(p_note,''),auth.uid()) returning id into new_id; return new_id;
end $$;
revoke all on function public.admin_wallet_adjust(uuid,bigint,text,text) from public,anon;
grant execute on function public.admin_wallet_adjust(uuid,bigint,text,text) to authenticated;
drop policy if exists approved_couriers_read_ready_orders on public.orders;
create policy approved_couriers_read_ready_orders on public.orders for select to authenticated using(status='ready_for_pickup' and courier_id is null and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='courier' and p.approval_status='approved'));
create or replace function public.claim_delivery_order(p_order_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
 if not exists(select 1 from public.profiles where id=v_uid and role='courier' and approval_status='approved') then raise exception 'حساب المندوب غير معتمد بعد'; end if;
 update public.orders set courier_id=v_uid,status='assigned',updated_at=now() where id=p_order_id and status='ready_for_pickup' and courier_id is null;
 if not found then raise exception 'الطلب لم يعد متاحاً للاستلام'; end if;
end $$;
revoke all on function public.claim_delivery_order(uuid) from public,anon;
grant execute on function public.claim_delivery_order(uuid) to authenticated;
drop policy if exists "restaurant members manage categories" on public.menu_categories;
create policy "restaurant members manage categories" on public.menu_categories for all to authenticated using(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved'))) with check(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved')));
drop policy if exists "restaurant members manage menu" on public.menu_items;
create policy "restaurant members manage menu" on public.menu_items for all to authenticated using(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved'))) with check(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved')));

-- Enforce approval in direct table updates as well as in RPC workflows.
drop policy if exists "restaurant managers update" on public.restaurants;
create policy "restaurant managers update" on public.restaurants for update to authenticated
using(public.is_admin() or (public.is_restaurant_member(id) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.approval_status='approved')))
with check(public.is_admin() or (public.is_restaurant_member(id) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.approval_status='approved')));
drop policy if exists "restaurant and courier update assigned orders" on public.orders;
create policy "restaurant and courier update assigned orders" on public.orders for update to authenticated
using(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.approval_status='approved')) or (courier_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='courier' and p.approval_status='approved')))
with check(public.is_admin() or (public.is_restaurant_member(restaurant_id) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.approval_status='approved')) or (courier_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='courier' and p.approval_status='approved')));


create or replace function public.transition_order(p_order_id uuid,p_next_status public.order_status,p_cancellation_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $
declare v_order public.orders%rowtype; v_uid uuid:=auth.uid(); v_allowed boolean:=false; v_role public.app_role; v_approval text;
begin
 if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
 select role,approval_status into v_role,v_approval from public.profiles where id=v_uid;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'الطلب غير موجود'; end if;
 if v_order.customer_id=v_uid then v_allowed:=v_order.status='pending' and p_next_status='cancelled';
 elsif public.is_admin() then
   v_allowed:=(v_order.status='pending' and p_next_status in('accepted','cancelled')) or (v_order.status='accepted' and p_next_status='preparing') or (v_order.status='preparing' and p_next_status='ready_for_pickup');
 elsif public.is_restaurant_member(v_order.restaurant_id) and v_approval='approved' then
   v_allowed:=(v_order.status='pending' and p_next_status in('accepted','cancelled')) or (v_order.status='accepted' and p_next_status='preparing') or (v_order.status='preparing' and p_next_status='ready_for_pickup');
 elsif v_order.courier_id=v_uid and v_role='courier' and v_approval='approved' then
   v_allowed:=(v_order.status='assigned' and p_next_status='picked_up') or (v_order.status='picked_up' and p_next_status='delivered');
 end if;
 if not v_allowed then raise exception 'لا يمكن تغيير حالة الطلب بهذه الصلاحية أو من هذه الحالة'; end if;
 update public.orders set status=p_next_status,cancellation_reason=case when p_next_status='cancelled' then coalesce(nullif(trim(p_cancellation_reason),''),'تم إلغاء الطلب') else cancellation_reason end,updated_at=now() where id=p_order_id;
end $;
revoke all on function public.transition_order(uuid,public.order_status,text) from public,anon;
grant execute on function public.transition_order(uuid,public.order_status,text) to authenticated;

notify pgrst,'reload schema';
commit;
