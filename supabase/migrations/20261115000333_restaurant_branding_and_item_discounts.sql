alter table public.restaurants
  add column if not exists cover_image_url text;

alter table public.promotions
  add column if not exists menu_item_id uuid references public.menu_items(id) on delete cascade;

create index if not exists promotions_menu_item_window_idx
  on public.promotions(menu_item_id, is_active, starts_at, ends_at);

create unique index if not exists promotions_one_active_per_menu_item_idx
  on public.promotions(menu_item_id)
  where menu_item_id is not null and is_active = true;

create or replace function public.validate_promotion_menu_item()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.menu_item_id is not null and not exists (
    select 1 from public.menu_items mi where mi.id = new.menu_item_id and mi.restaurant_id = new.restaurant_id
  ) then
    raise exception 'يجب اختيار صنف تابع للمطعم نفسه';
  end if;
  return new;
end;
$$;

drop trigger if exists promotions_validate_menu_item on public.promotions;
create trigger promotions_validate_menu_item
before insert or update of restaurant_id, menu_item_id on public.promotions
for each row execute function public.validate_promotion_menu_item();

create or replace function public.effective_menu_item_price(p_menu_item_id uuid, p_restaurant_id uuid, p_base_price integer)
returns integer language plpgsql stable security invoker set search_path = public as $$
declare v_discount_type text; v_discount_value integer;
begin
  select p.discount_type, p.discount_value into v_discount_type, v_discount_value
  from public.promotions p
  where p.menu_item_id = p_menu_item_id and p.restaurant_id = p_restaurant_id
    and p.is_active = true and p.starts_at <= now() and (p.ends_at is null or p.ends_at > now())
  order by p.starts_at desc limit 1;
  if not found then return p_base_price; end if;
  if v_discount_type = 'percentage' then
    return greatest(1, floor(p_base_price::numeric * (100 - v_discount_value) / 100)::integer);
  end if;
  return greatest(1, p_base_price - v_discount_value);
end;
$$;

revoke all on function public.effective_menu_item_price(uuid, uuid, integer) from public, anon;
grant execute on function public.effective_menu_item_price(uuid, uuid, integer) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('restaurant-covers', 'restaurant-covers', true, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 8388608, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "restaurant members upload restaurant covers" on storage.objects;
create policy "restaurant members upload restaurant covers" on storage.objects for insert to authenticated
with check (bucket_id = 'restaurant-covers' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));

drop policy if exists "restaurant members update restaurant covers" on storage.objects;
create policy "restaurant members update restaurant covers" on storage.objects for update to authenticated
using (bucket_id = 'restaurant-covers' and public.is_restaurant_member((storage.foldername(name))[1]::uuid))
with check (bucket_id = 'restaurant-covers' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));

drop policy if exists "restaurant members delete restaurant covers" on storage.objects;
create policy "restaurant members delete restaurant covers" on storage.objects for delete to authenticated
using (bucket_id = 'restaurant-covers' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));

create or replace function public.create_order(
  p_restaurant_id uuid, p_customer_name text, p_customer_phone text, p_delivery_address text,
  p_items jsonb, p_delivery_latitude double precision, p_delivery_longitude double precision, p_notes text default ''
)
returns uuid language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_restaurant public.restaurants%rowtype;
  v_order_id uuid;
  v_item jsonb;
  v_menu public.menu_items%rowtype;
  v_qty integer;
  v_subtotal integer := 0;
  v_lat double precision := p_delivery_latitude;
  v_lng double precision := p_delivery_longitude;
  v_match text[];
  v_hours public.restaurant_hours%rowtype;
  v_local_day smallint;
  v_local_time time;
  v_unit_price integer;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول أولاً'; end if;
  if exists (select 1 from public.profiles where id = v_uid and is_blocked = true) then
    raise exception 'تم إيقاف حسابك من إدارة سريع. تواصل مع الدعم إذا كنت ترى أن هذا الإيقاف بالخطأ.';
  end if;
  if length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'اسم المستلم غير صحيح'; end if;
  if length(trim(coalesce(p_customer_phone,''))) < 7 then raise exception 'رقم الهاتف غير صحيح'; end if;
  if length(trim(coalesce(p_delivery_address,''))) < 5 then raise exception 'عنوان التوصيل غير مكتمل'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'السلة فارغة'; end if;
  if v_lat is null or v_lng is null then
    v_match := regexp_match(p_delivery_address, 'الموقع:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*[,،]\s*(-?[0-9]+(?:\.[0-9]+)?)');
    if v_match is not null then v_lat := v_match[1]::double precision; v_lng := v_match[2]::double precision; end if;
  end if;
  if (v_lat is null) <> (v_lng is null) or (v_lat is not null and (abs(v_lat) > 90 or abs(v_lng) > 180)) then
    raise exception 'إحداثيات موقع التوصيل غير صحيحة';
  end if;
  select * into v_restaurant from public.restaurants where id = p_restaurant_id and is_active = true for share;
  if not found then raise exception 'المطعم غير متاح حالياً'; end if;

  if exists (select 1 from public.restaurant_hours where restaurant_id = p_restaurant_id) then
    v_local_day := extract(dow from (now() at time zone 'Asia/Aden'))::smallint;
    v_local_time := (now() at time zone 'Asia/Aden')::time;
    select * into v_hours from public.restaurant_hours where restaurant_id = p_restaurant_id and weekday = v_local_day limit 1;
    if not found or v_hours.is_closed then raise exception 'المطعم مغلق اليوم'; end if;
    if v_hours.opens_at is null or v_hours.closes_at is null then raise exception 'أوقات عمل المطعم غير مكتملة'; end if;
    if v_hours.opens_at < v_hours.closes_at then
      if v_local_time < v_hours.opens_at or v_local_time > v_hours.closes_at then raise exception 'المطعم خارج أوقات العمل حالياً'; end if;
    elsif v_hours.opens_at > v_hours.closes_at then
      if v_local_time < v_hours.opens_at and v_local_time > v_hours.closes_at then raise exception 'المطعم خارج أوقات العمل حالياً'; end if;
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if coalesce(v_item->>'menu_item_id','') = '' then raise exception 'يوجد صنف غير صالح في السلة'; end if;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'كمية الصنف غير صالحة'; end if;
    select * into v_menu from public.menu_items
      where id = (v_item->>'menu_item_id')::uuid and restaurant_id = p_restaurant_id
        and is_available = true and price_yer > 0 for share;
    if not found then raise exception 'أحد الأصناف لم يعد متاحاً للطلب'; end if;
    v_unit_price := public.effective_menu_item_price(v_menu.id, p_restaurant_id, v_menu.price_yer);
    v_subtotal := v_subtotal + (v_unit_price * v_qty);
  end loop;

  if v_subtotal < coalesce(v_restaurant.minimum_order_yer, 0) then
    raise exception 'الحد الأدنى للطلب من هذا المطعم هو % ريال', v_restaurant.minimum_order_yer;
  end if;

  insert into public.orders(customer_id, restaurant_id, status, customer_name, customer_phone, delivery_address,
    delivery_latitude, delivery_longitude, subtotal_yer, delivery_fee_yer, total_yer, payment_method, notes)
  values(v_uid, p_restaurant_id, 'pending', trim(p_customer_name), trim(p_customer_phone), trim(p_delivery_address),
    v_lat, v_lng, v_subtotal, v_restaurant.delivery_fee_yer, v_subtotal + v_restaurant.delivery_fee_yer,
    'cash_on_delivery', coalesce(p_notes,''))
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_menu from public.menu_items where id = (v_item->>'menu_item_id')::uuid and restaurant_id = p_restaurant_id;
    v_unit_price := public.effective_menu_item_price(v_menu.id, p_restaurant_id, v_menu.price_yer);
    insert into public.order_items(order_id, menu_item_id, item_name, unit_price_yer, quantity)
    values(v_order_id, v_menu.id, v_menu.name, v_unit_price, v_qty);
  end loop;
  return v_order_id;
end;
$function$;

revoke all on function public.create_order(uuid, text, text, text, jsonb, double precision, double precision, text) from public, anon;
grant execute on function public.create_order(uuid, text, text, text, jsonb, double precision, double precision, text) to authenticated;
