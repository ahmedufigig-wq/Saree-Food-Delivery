begin;

create table if not exists public.promotion_menu_items (
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (promotion_id, menu_item_id)
);
create index if not exists promotion_menu_items_menu_item_idx on public.promotion_menu_items(menu_item_id, promotion_id);
alter table public.promotion_menu_items enable row level security;
revoke all on public.promotion_menu_items from anon, authenticated;
grant select, insert, update, delete on public.promotion_menu_items to authenticated;
create policy promotion_items_read_active_or_restaurant on public.promotion_menu_items for select to authenticated
using (exists(select 1 from public.promotions p where p.id=promotion_id and ((p.is_active and p.starts_at<=now() and (p.ends_at is null or p.ends_at>now())) or public.is_restaurant_member(p.restaurant_id))));
create policy promotion_items_manage_restaurant on public.promotion_menu_items for all to authenticated
using (exists(select 1 from public.promotions p where p.id=promotion_id and public.is_restaurant_member(p.restaurant_id)))
with check (exists(select 1 from public.promotions p where p.id=promotion_id and public.is_restaurant_member(p.restaurant_id)));

create or replace function public.validate_promotion_menu_item_link()
returns trigger language plpgsql set search_path=public as $$
begin
 if not exists(select 1 from public.promotions p join public.menu_items mi on mi.id=new.menu_item_id where p.id=new.promotion_id and p.restaurant_id=mi.restaurant_id) then
  raise exception 'يجب أن تكون جميع أصناف العرض تابعة للمطعم نفسه';
 end if;
 return new;
end; $$;
create trigger promotion_menu_items_validate before insert or update on public.promotion_menu_items for each row execute function public.validate_promotion_menu_item_link();

create or replace function public.effective_menu_item_price(p_menu_item_id uuid,p_restaurant_id uuid,p_base_price integer)
returns integer language plpgsql stable security invoker set search_path=public as $$
declare v_discount_type text; v_discount_value integer;
begin
 select p.discount_type,p.discount_value into v_discount_type,v_discount_value from public.promotions p
 where p.restaurant_id=p_restaurant_id and p.is_active=true and p.starts_at<=now() and (p.ends_at is null or p.ends_at>now())
 and (p.menu_item_id=p_menu_item_id or exists(select 1 from public.promotion_menu_items pmi where pmi.promotion_id=p.id and pmi.menu_item_id=p_menu_item_id))
 order by p.starts_at desc limit 1;
 if not found then return p_base_price; end if;
 if v_discount_type='percentage' then return greatest(1,floor(p_base_price::numeric*(100-v_discount_value)/100)::integer); end if;
 return greatest(1,p_base_price-v_discount_value);
end; $$;
revoke all on function public.effective_menu_item_price(uuid,uuid,integer) from public,anon;
grant execute on function public.effective_menu_item_price(uuid,uuid,integer) to authenticated;

create table if not exists public.restaurant_courier_history (
 id uuid primary key default gen_random_uuid(),
 restaurant_id uuid not null references public.restaurants(id) on delete cascade,
 courier_id uuid not null references public.profiles(id),
 courier_name text not null default '',
 courier_phone text,
 courier_email text,
 event_type text not null check(event_type in ('accepted','removed','restored')),
 event_at timestamptz not null default now(),
 actor_id uuid references public.profiles(id),
 note text
);
create index if not exists restaurant_courier_history_restaurant_time_idx on public.restaurant_courier_history(restaurant_id,event_at desc);
alter table public.restaurant_courier_history enable row level security;
revoke all on public.restaurant_courier_history from anon,authenticated;
grant select on public.restaurant_courier_history to authenticated;
create policy restaurant_courier_history_read_member on public.restaurant_courier_history for select to authenticated using(public.is_restaurant_member(restaurant_id));

create or replace function public.log_restaurant_courier_history()
returns trigger language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_name text; v_phone text; v_email text;
begin
 if tg_op='DELETE' then
  select p.full_name,p.phone,u.email into v_name,v_phone,v_email from public.profiles p left join auth.users u on u.id=p.id where p.id=old.courier_id;
  insert into public.restaurant_courier_history(restaurant_id,courier_id,courier_name,courier_phone,courier_email,event_type,actor_id,note)
  values(old.restaurant_id,old.courier_id,coalesce(v_name,''),v_phone,v_email,'removed',auth.uid(),'إزالة المندوب من فريق المطعم');
  return old;
 elsif tg_op='INSERT' then
  select p.full_name,p.phone,u.email into v_name,v_phone,v_email from public.profiles p left join auth.users u on u.id=p.id where p.id=new.courier_id;
  insert into public.restaurant_courier_history(restaurant_id,courier_id,courier_name,courier_phone,courier_email,event_type,actor_id,note)
  values(new.restaurant_id,new.courier_id,coalesce(v_name,''),v_phone,v_email,'accepted',auth.uid(),'إضافة المندوب إلى فريق المطعم');
 elsif old.is_active=false and new.is_active=true then
  select p.full_name,p.phone,u.email into v_name,v_phone,v_email from public.profiles p left join auth.users u on u.id=p.id where p.id=new.courier_id;
  insert into public.restaurant_courier_history(restaurant_id,courier_id,courier_name,courier_phone,courier_email,event_type,actor_id,note)
  values(new.restaurant_id,new.courier_id,coalesce(v_name,''),v_phone,v_email,'restored',auth.uid(),'إعادة تفعيل المندوب ضمن فريق المطعم');
 end if;
 return new;
end; $$;
revoke all on function public.log_restaurant_courier_history() from public,anon,authenticated;
create trigger restaurant_courier_history_insert after insert on public.restaurant_couriers for each row execute function public.log_restaurant_courier_history();
create trigger restaurant_courier_history_delete before delete on public.restaurant_couriers for each row execute function public.log_restaurant_courier_history();
create trigger restaurant_courier_history_restore after update of is_active on public.restaurant_couriers for each row execute function public.log_restaurant_courier_history();
notify pgrst,'reload schema';
commit;
