-- Align courier-to-restaurant applications with the new identity precheck.
-- Old uploads with image_precheck_passed=false must be resubmitted.

create or replace function public.courier_apply_to_restaurants(p_restaurant_ids uuid[])
returns integer
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_count integer := 0;
  v_restaurant_name text;
  v_document_count integer;
begin
  if v_uid is null then
    raise exception 'يرجى تسجيل الدخول مرة أخرى';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'courier' and p.is_blocked = false
      and p.approval_status = 'approved'
  ) then
    raise exception 'لا يمكن إرسال طلب العمل قبل إكمال فحص الهوية. أعد رفع صور البطاقة والسيلفي الواضحة أولاً.';
  end if;

  if p_restaurant_ids is null or cardinality(p_restaurant_ids) = 0 then
    raise exception 'اختر مطعماً واحداً على الأقل';
  end if;
  if cardinality(p_restaurant_ids) > 30 then
    raise exception 'يمكن اختيار 30 مطعماً كحد أقصى في الطلب الواحد';
  end if;

  select count(distinct d.document_type)
    into v_document_count
  from public.courier_verification_documents d
  join storage.objects o
    on o.bucket_id = 'courier-verification'
   and o.name = d.storage_path
  where d.courier_id = v_uid
    and d.image_precheck_passed = true
    and d.document_type in ('id_front', 'id_back', 'selfie')
    and d.storage_path like v_uid::text || '/%';

  if v_document_count <> 3 then
    raise exception 'صور الهوية المسجلة قديمة أو لم تجتز الفحص. أعد رفع الوجهين والسيلفي من داخل التطبيق.';
  end if;

  for v_id in select distinct unnest(p_restaurant_ids)
  loop
    select r.name into v_restaurant_name
    from public.restaurants r
    where r.id = v_id and r.is_active = true;

    if v_restaurant_name is null then
      raise exception 'المطعم المختار غير متاح حالياً. حدّث قائمة المطاعم وحاول مجدداً.';
    end if;

    insert into public.courier_restaurant_applications
      (courier_id, restaurant_id, status)
    values (v_uid, v_id, 'pending')
    on conflict (courier_id, restaurant_id) do update
      set status = 'pending', created_at = now(),
          reviewed_at = null, review_note = null
      where public.courier_restaurant_applications.status = 'rejected';

    if found then
      v_count := v_count + 1;
      insert into public.notifications(user_id, title, body, kind)
      select rm.user_id,
        'طلب انضمام مندوب جديد',
        'أرسل ' || coalesce(
          (select p.full_name from public.profiles p where p.id = v_uid),
          'مندوب'
        ) || ' طلباً للانضمام إلى فريق توصيل مطعم ' || v_restaurant_name || '.',
        'courier_application'
      from public.restaurant_members rm
      join public.profiles rp on rp.id = rm.user_id
      where rm.restaurant_id = v_id
        and rp.role = 'restaurant_owner'
        and rp.approval_status = 'approved'
        and rp.is_blocked = false;
    end if;
  end loop;

  return v_count;
end;
$function$;

revoke all on function public.courier_apply_to_restaurants(uuid[]) from public, anon;
grant execute on function public.courier_apply_to_restaurants(uuid[]) to authenticated;

notify pgrst, 'reload schema';
