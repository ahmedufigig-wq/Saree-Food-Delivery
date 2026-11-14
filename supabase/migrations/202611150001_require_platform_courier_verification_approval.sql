begin;
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if (new.role is distinct from old.role or new.approval_status is distinct from old.approval_status or new.approved_at is distinct from old.approved_at)
     and not public.is_admin() then
    if current_setting('saree.allow_courier_verification_pending', true) = 'on'
       and auth.uid() = old.id and old.role = 'courier' and new.role = old.role
       and new.approval_status = 'pending' and new.approved_at is null then return new; end if;
    raise exception 'تغيير الدور أو الاعتماد متاح للمدير فقط';
  end if;
  return new;
end; $$;

create or replace function public.submit_courier_verification_for_review()
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and role='courier' and is_blocked=false) then
    raise exception 'هذه الخدمة متاحة لحسابات المندوبين فقط';
  end if;
  if (select count(distinct d.document_type) from public.courier_verification_documents d
      join storage.objects o on o.bucket_id='courier-verification' and o.name=d.storage_path
      where d.courier_id=v_uid and d.document_type in ('id_front','id_back','selfie')
        and d.storage_path like v_uid::text || '/%') <> 3 then
    raise exception 'لم تكتمل صور الهوية والسيلفي؛ أعد إرسال المستندات المطلوبة';
  end if;
  perform set_config('saree.allow_courier_verification_pending','on',true);
  update public.profiles set approval_status='pending',approval_requested_at=now(),approved_at=null,approval_note=null
  where id=v_uid and role='courier';
end; $$;

create or replace function public.admin_review_user(p_user_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare target_role text;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'متاح للمدير فقط'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'قرار اعتماد غير صالح'; end if;
  select role into target_role from public.profiles where id=p_user_id for update;
  if not found then raise exception 'الحساب غير موجود'; end if;
  if target_role in ('customer','admin') then raise exception 'هذا الحساب لا يحتاج اعتماداً'; end if;
  if target_role='courier' and p_decision='approved' and (
    select count(distinct d.document_type) from public.courier_verification_documents d
    join storage.objects o on o.bucket_id='courier-verification' and o.name=d.storage_path
    where d.courier_id=p_user_id and d.document_type in ('id_front','id_back','selfie')
      and d.storage_path like p_user_id::text || '/%'
  ) <> 3 then
    raise exception 'لا يمكن اعتماد المندوب قبل استلام صورة الهوية الأمامية والخلفية والسيلفي مع البطاقة';
  end if;
  update public.profiles set approval_status=p_decision,
    approved_at=case when p_decision='approved' then now() else null end,
    approval_note=nullif(trim(coalesce(p_note,'')),'') where id=p_user_id;
end; $$;

create or replace function public.courier_apply_to_restaurants(p_restaurant_ids uuid[])
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_count integer:=0; v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='courier' and p.approval_status='approved' and p.is_blocked=false) then
    raise exception 'يجب اعتماد هويتك من إدارة سريع أولاً قبل التقديم للمطاعم';
  end if;
  if p_restaurant_ids is null or cardinality(p_restaurant_ids)=0 then raise exception 'اختر مطعماً واحداً على الأقل'; end if;
  if cardinality(p_restaurant_ids)>30 then raise exception 'يمكن اختيار 30 مطعماً كحد أقصى في الطلب الواحد'; end if;
  if (select count(distinct d.document_type) from public.courier_verification_documents d
      join storage.objects o on o.bucket_id='courier-verification' and o.name=d.storage_path
      where d.courier_id=v_uid and d.document_type in ('id_front','id_back','selfie')
        and d.storage_path like v_uid::text || '/%') <> 3 then
    raise exception 'أكمل توثيق الهوية واعتمادها من إدارة سريع أولاً';
  end if;
  foreach v_id in array (select distinct unnest(p_restaurant_ids)) loop
    select r.name into v_restaurant_name from public.restaurants r where r.id=v_id and r.is_active=true;
    if v_restaurant_name is null then raise exception 'أحد المطاعم المختارة غير متاح حالياً'; end if;
    insert into public.courier_restaurant_applications(courier_id,restaurant_id,status) values(v_uid,v_id,'pending')
    on conflict(courier_id,restaurant_id) do update
      set status='pending',created_at=now(),reviewed_at=null,review_note=null
      where public.courier_restaurant_applications.status='rejected';
    if found then
      v_count:=v_count+1;
      insert into public.notifications(user_id,title,body,kind)
      select rm.user_id,'طلب انضمام مندوب جديد',
        'أرسل '||coalesce((select p.full_name from public.profiles p where p.id=v_uid),'مندوب')||
        ' طلباً للانضمام إلى فريق توصيل مطعم '||v_restaurant_name||'.','courier_application'
      from public.restaurant_members rm join public.profiles rp on rp.id=rm.user_id
      where rm.restaurant_id=v_id and rp.role='restaurant_owner' and rp.approval_status='approved' and rp.is_blocked=false;
    end if;
  end loop;
  return v_count;
end; $$;

create or replace function public.restaurant_courier_applications(p_restaurant_id uuid)
returns table(application_id uuid,courier_id uuid,full_name text,phone text,email text,status text,created_at timestamptz,id_front_path text,id_back_path text,selfie_path text,platform_approval_status text)
language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='restaurant_owner' and p.approval_status='approved' and p.is_blocked=false)
    or not public.is_restaurant_member(p_restaurant_id) then raise exception 'ليس لديك صلاحية مراجعة طلبات مندوبي هذا المطعم'; end if;
  return query
  select a.id,p.id,p.full_name,p.phone,u.email,a.status,a.created_at,
    (select d.storage_path from public.courier_verification_documents d where d.courier_id=p.id and d.document_type='id_front' order by d.created_at desc limit 1),
    (select d.storage_path from public.courier_verification_documents d where d.courier_id=p.id and d.document_type='id_back' order by d.created_at desc limit 1),
    (select d.storage_path from public.courier_verification_documents d where d.courier_id=p.id and d.document_type='selfie' order by d.created_at desc limit 1),
    p.approval_status
  from public.courier_restaurant_applications a join public.profiles p on p.id=a.courier_id
  left join auth.users u on u.id=p.id
  where a.restaurant_id=p_restaurant_id and p.approval_status='approved'
  order by case a.status when 'pending' then 0 when 'accepted' then 1 else 2 end,a.created_at desc;
end; $$;

create or replace function public.restaurant_review_courier_application(p_application_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_app public.courier_restaurant_applications%rowtype; v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if p_decision not in ('accepted','rejected') then raise exception 'قرار غير صالح'; end if;
  select a.* into v_app from public.courier_restaurant_applications a where a.id=p_application_id for update;
  if not found then raise exception 'طلب الانضمام غير موجود'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='restaurant_owner' and p.approval_status='approved' and p.is_blocked=false)
    or not public.is_restaurant_member(v_app.restaurant_id) then raise exception 'ليس لديك صلاحية مراجعة هذا الطلب'; end if;
  if v_app.status<>'pending' then raise exception 'تمت مراجعة هذا الطلب من قبل'; end if;
  if p_decision='accepted' and not exists(select 1 from public.profiles p where p.id=v_app.courier_id and p.role='courier' and p.approval_status='approved' and p.is_blocked=false)
    then raise exception 'لا يمكن قبول المندوب قبل اعتماد هويته من إدارة سريع'; end if;
  if p_decision='accepted' and (
    select count(distinct d.document_type) from public.courier_verification_documents d
    join storage.objects o on o.bucket_id='courier-verification' and o.name=d.storage_path
    where d.courier_id=v_app.courier_id and d.document_type in ('id_front','id_back','selfie')
      and d.storage_path like v_app.courier_id::text || '/%'
  ) <> 3 then raise exception 'لا يمكن قبول المندوب قبل اكتمال مستندات الهوية'; end if;
  update public.courier_restaurant_applications set status=p_decision,reviewed_at=now(),review_note=nullif(trim(coalesce(p_note,'')),'') where id=p_application_id;
  select r.name into v_restaurant_name from public.restaurants r where r.id=v_app.restaurant_id;
  if p_decision='accepted' then
    insert into public.restaurant_couriers(restaurant_id,courier_id,is_active,added_by) values(v_app.restaurant_id,v_app.courier_id,true,v_uid)
    on conflict(restaurant_id,courier_id) do update set is_active=true,added_by=excluded.added_by,updated_at=now();
    insert into public.notifications(user_id,title,body,kind) values(v_app.courier_id,'تم قبول طلب انضمامك إلى مطعم',
      'وافق مطعم '||coalesce(v_restaurant_name,'')||' على انضمامك إلى فريق التوصيل.','restaurant_application');
  else
    insert into public.notifications(user_id,title,body,kind) values(v_app.courier_id,'تم رفض طلب الانضمام إلى مطعم',
      'لم يوافق مطعم '||coalesce(v_restaurant_name,'')||' على طلب انضمامك.','restaurant_application');
  end if;
end; $$;

revoke all on function public.submit_courier_verification_for_review() from public,anon;
grant execute on function public.submit_courier_verification_for_review() to authenticated;
revoke all on function public.courier_apply_to_restaurants(uuid[]) from public,anon;
revoke all on function public.restaurant_courier_applications(uuid) from public,anon;
revoke all on function public.restaurant_review_courier_application(uuid,text,text) from public,anon;
grant execute on function public.courier_apply_to_restaurants(uuid[]) to authenticated;
grant execute on function public.restaurant_courier_applications(uuid) to authenticated;
grant execute on function public.restaurant_review_courier_application(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;