begin;

create table if not exists public.courier_restaurant_applications (
  id uuid primary key default gen_random_uuid(),
  courier_id uuid not null references public.profiles(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  review_note text,
  unique (courier_id, restaurant_id)
);
create index if not exists courier_restaurant_applications_restaurant_status_idx
  on public.courier_restaurant_applications (restaurant_id, status, created_at desc);
create index if not exists courier_restaurant_applications_courier_idx
  on public.courier_restaurant_applications (courier_id, created_at desc);
alter table public.courier_restaurant_applications enable row level security;
revoke all on public.courier_restaurant_applications from anon, authenticated;

create or replace function public.courier_apply_to_restaurants(p_restaurant_ids uuid[])
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_count integer:=0; v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='courier' and p.is_blocked=false) then raise exception 'هذه الخدمة متاحة لحسابات المندوبين فقط'; end if;
  if p_restaurant_ids is null or cardinality(p_restaurant_ids)=0 then raise exception 'اختر مطعماً واحداً على الأقل'; end if;
  if cardinality(p_restaurant_ids)>30 then raise exception 'يمكن اختيار 30 مطعماً كحد أقصى في الطلب الواحد'; end if;
  if not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_uid and d.document_type='id_front')
     or not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_uid and d.document_type='id_back')
     or not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_uid and d.document_type='selfie') then
    raise exception 'أكمل رفع الهوية الأمامية والخلفية والسيلفي مع البطاقة أولاً';
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

create or replace function public.courier_my_restaurant_applications()
returns table(application_id uuid,restaurant_id uuid,restaurant_name text,status text,created_at timestamptz,review_note text)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='courier') then raise exception 'هذه الخدمة متاحة للمندوبين فقط'; end if;
  return query select a.id,a.restaurant_id,r.name,a.status,a.created_at,a.review_note
    from public.courier_restaurant_applications a join public.restaurants r on r.id=a.restaurant_id
    where a.courier_id=v_uid order by a.created_at desc;
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
  left join auth.users u on u.id=p.id where a.restaurant_id=p_restaurant_id
  order by case a.status when 'pending' then 0 when 'accepted' then 1 else 2 end,a.created_at desc;
end; $$;

create or replace function public.restaurant_review_courier_application(p_application_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_app public.courier_restaurant_applications%rowtype; v_restaurant_name text; v_courier_approval text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if p_decision not in ('accepted','rejected') then raise exception 'قرار غير صالح'; end if;
  select a.* into v_app from public.courier_restaurant_applications a where a.id=p_application_id for update;
  if not found then raise exception 'طلب الانضمام غير موجود'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='restaurant_owner' and p.approval_status='approved' and p.is_blocked=false)
    or not public.is_restaurant_member(v_app.restaurant_id) then raise exception 'ليس لديك صلاحية مراجعة هذا الطلب'; end if;
  if v_app.status<>'pending' then raise exception 'تمت مراجعة هذا الطلب من قبل'; end if;
  select p.approval_status into v_courier_approval from public.profiles p where p.id=v_app.courier_id;
  if p_decision='accepted' and v_courier_approval<>'approved' then raise exception 'لا يمكن قبول المندوب قبل اعتماد هويته من إدارة سريع'; end if;
  update public.courier_restaurant_applications set status=p_decision,reviewed_at=now(),review_note=nullif(trim(coalesce(p_note,'')),'') where id=p_application_id;
  select r.name into v_restaurant_name from public.restaurants r where r.id=v_app.restaurant_id;
  if p_decision='accepted' then
    insert into public.restaurant_couriers(restaurant_id,courier_id,is_active,added_by) values(v_app.restaurant_id,v_app.courier_id,true,v_uid)
    on conflict(restaurant_id,courier_id) do update set is_active=true,added_by=excluded.added_by,updated_at=now();
    insert into public.notifications(user_id,title,body,kind) values(v_app.courier_id,'تم قبول طلب انضمامك إلى مطعم','وافق مطعم '||coalesce(v_restaurant_name,'')||' على انضمامك إلى فريق التوصيل.','restaurant_application');
  else
    insert into public.notifications(user_id,title,body,kind) values(v_app.courier_id,'تم رفض طلب الانضمام إلى مطعم','لم يوافق مطعم '||coalesce(v_restaurant_name,'')||' على طلب انضمامك.','restaurant_application');
  end if;
end; $$;

drop policy if exists courier_verification_read_own_or_admin on storage.objects;
drop policy if exists courier_verification_read_own_admin_or_applying_restaurant on storage.objects;
create policy courier_verification_read_own_admin_or_applying_restaurant on storage.objects for select to authenticated
using (
  bucket_id='courier-verification' and (
    (storage.foldername(name))[1]=(select auth.uid())::text or public.is_admin()
    or exists(
      select 1 from public.courier_restaurant_applications a
      join public.restaurant_members rm on rm.restaurant_id=a.restaurant_id
      join public.profiles rp on rp.id=rm.user_id
      where a.courier_id=((storage.foldername(name))[1])::uuid
        and a.status in ('pending','accepted') and rm.user_id=(select auth.uid())
        and rp.role='restaurant_owner' and rp.approval_status='approved' and rp.is_blocked=false
    )
  )
);

revoke all on function public.courier_apply_to_restaurants(uuid[]) from public,anon;
revoke all on function public.courier_my_restaurant_applications() from public,anon;
revoke all on function public.restaurant_courier_applications(uuid) from public,anon;
revoke all on function public.restaurant_review_courier_application(uuid,text,text) from public,anon;
grant execute on function public.courier_apply_to_restaurants(uuid[]) to authenticated;
grant execute on function public.courier_my_restaurant_applications() to authenticated;
grant execute on function public.restaurant_courier_applications(uuid) to authenticated;
grant execute on function public.restaurant_review_courier_application(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;