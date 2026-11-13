-- Use the existing restaurant_hours table as the single source of weekly schedules.
-- An empty schedule keeps the current behavior (no hours restriction).
alter table public.restaurants drop column if exists opening_hours;

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
  v_hours public.restaurant_hours%rowtype;
  v_local_day smallint;
  v_local_time time;
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

  -- Weekly schedule uses the pre-existing restaurant_hours table (0=Sunday..6=Saturday).
  -- No schedule rows means keep the restaurant's existing always-accept-orders behavior.
  if exists (select 1 from public.restaurant_hours where restaurant_id = p_restaurant_id) then
    v_local_day := extract(dow from (now() at time zone 'Asia/Aden'))::smallint;
    v_local_time := (now() at time zone 'Asia/Aden')::time;
    select * into v_hours
      from public.restaurant_hours
      where restaurant_id = p_restaurant_id and weekday = v_local_day
      limit 1;
    if not found or v_hours.is_closed then
      raise exception 'المطعم مغلق اليوم';
    end if;
    if v_hours.opens_at is null or v_hours.closes_at is null then
      raise exception 'أوقات عمل المطعم غير مكتملة';
    end if;
    if v_hours.opens_at < v_hours.closes_at then
      if v_local_time < v_hours.opens_at or v_local_time > v_hours.closes_at then
        raise exception 'المطعم خارج أوقات العمل حالياً';
      end if;
    elsif v_hours.opens_at > v_hours.closes_at then
      if v_local_time < v_hours.opens_at and v_local_time > v_hours.closes_at then
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
