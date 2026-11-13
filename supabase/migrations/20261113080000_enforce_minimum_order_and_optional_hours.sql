-- Server-side order rules for minimum basket and optional restaurant working hours.
-- Existing restaurants remain unrestricted because opening_hours defaults to NULL.
-- Existing minimum_order_yer values are preserved (currently 0 for both restaurants).
alter table public.restaurants
  add column if not exists opening_hours jsonb;

comment on column public.restaurants.opening_hours is
  'Optional weekly schedule in Asia/Aden local time. JSON keys 0=Sunday through 6=Saturday; each value: {"open":"09:00","close":"23:00","closed":false}. NULL means no schedule restriction.';

create or replace function public.create_order(
  p_restaurant_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_items jsonb,
  p_delivery_latitude double precision,
  p_delivery_longitude double precision,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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
  v_schedule jsonb;
  v_local_day text;
  v_local_time time;
  v_open time;
  v_close time;
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
    if v_match is not null then
      v_lat := v_match[1]::double precision;
      v_lng := v_match[2]::double precision;
    end if;
  end if;
  if (v_lat is null) <> (v_lng is null)
     or (v_lat is not null and (abs(v_lat) > 90 or abs(v_lng) > 180)) then
    raise exception 'إحداثيات موقع التوصيل غير صحيحة';
  end if;

  select * into v_restaurant from public.restaurants
  where id = p_restaurant_id and is_active = true for share;
  if not found then raise exception 'المطعم غير متاح حالياً'; end if;

  -- Optional weekly working-hours enforcement. NULL preserves current always-open behavior.
  if v_restaurant.opening_hours is not null then
    v_local_day := extract(dow from (now() at time zone 'Asia/Aden'))::integer::text;
    v_local_time := (now() at time zone 'Asia/Aden')::time;
    v_schedule := v_restaurant.opening_hours -> v_local_day;
    if v_schedule is null then
      raise exception 'المطعم لا يستقبل الطلبات في هذا اليوم';
    end if;
    if coalesce((v_schedule ->> 'closed')::boolean, false) then
      raise exception 'المطعم مغلق اليوم';
    end if;
    if coalesce(v_schedule ->> 'open', '') = '' or coalesce(v_schedule ->> 'close', '') = '' then
      raise exception 'أوقات عمل المطعم غير مكتملة';
    end if;
    v_open := (v_schedule ->> 'open')::time;
    v_close := (v_schedule ->> 'close')::time;
    if v_open = v_close then
      null; -- Equal times explicitly mean open all day.
    elsif v_open < v_close then
      if v_local_time < v_open or v_local_time > v_close then
        raise exception 'المطعم خارج أوقات العمل حالياً';
      end if;
    else
      if v_local_time < v_open and v_local_time > v_close then
        raise exception 'المطعم خارج أوقات العمل حالياً';
      end if;
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item->>'menu_item_id','') = '' then raise exception 'يوجد صنف غير صالح في السلة'; end if;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'كمية الصنف غير صالحة'; end if;
    select * into v_menu from public.menu_items
    where id = (v_item->>'menu_item_id')::uuid
      and restaurant_id = p_restaurant_id and is_available = true and price_yer > 0
    for share;
    if not found then raise exception 'أحد الأصناف لم يعد متاحاً للطلب'; end if;
    v_subtotal := v_subtotal + (v_menu.price_yer * v_qty);
  end loop;

  if v_subtotal < coalesce(v_restaurant.minimum_order_yer, 0) then
    raise exception 'الحد الأدنى للطلب من هذا المطعم هو % ريال', v_restaurant.minimum_order_yer;
  end if;

  insert into public.orders (
    customer_id, restaurant_id, status, customer_name, customer_phone,
    delivery_address, delivery_latitude, delivery_longitude,
    subtotal_yer, delivery_fee_yer, total_yer, payment_method, notes
  ) values (
    v_uid, p_restaurant_id, 'pending', trim(p_customer_name), trim(p_customer_phone),
    trim(p_delivery_address), v_lat, v_lng,
    v_subtotal, v_restaurant.delivery_fee_yer, v_subtotal + v_restaurant.delivery_fee_yer,
    'cash_on_delivery', coalesce(p_notes,'')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_menu from public.menu_items where id = (v_item->>'menu_item_id')::uuid and restaurant_id = p_restaurant_id;
    insert into public.order_items(order_id, menu_item_id, item_name, unit_price_yer, quantity)
    values (v_order_id, v_menu.id, v_menu.name, v_menu.price_yer, v_qty);
  end loop;
  return v_order_id;
end;
$function$;

notify pgrst, 'reload schema';
