-- Allow restaurants to accept a courier after account creation, login, and complete identity documents.
-- Platform-wide admin approval is not required for restaurant membership.
create or replace function public.restaurant_review_courier_application(p_application_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_app public.courier_restaurant_applications%rowtype; v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if p_decision not in ('accepted','rejected') then raise exception 'قرار غير صالح'; end if;
  select a.* into v_app from public.courier_restaurant_applications a where a.id=p_application_id for update;
  if not found then raise exception 'طلب الانضمام غير موجود'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='restaurant_owner' and p.approval_status='approved' and p.is_blocked=false)
    or not public.is_restaurant_member(v_app.restaurant_id) then raise exception 'ليس لديك صلاحية مراجعة هذا الطلب'; end if;
  if v_app.status<>'pending' then raise exception 'تمت مراجعة هذا الطلب من قبل'; end if;
  if p_decision='accepted' and not exists(
    select 1 from public.profiles p where p.id=v_app.courier_id and p.role='courier' and p.is_blocked=false
  ) then raise exception 'حساب المندوب غير مكتمل أو غير متاح'; end if;
  if p_decision='accepted' and (
    not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_app.courier_id and d.document_type='id_front')
    or not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_app.courier_id and d.document_type='id_back')
    or not exists(select 1 from public.courier_verification_documents d where d.courier_id=v_app.courier_id and d.document_type='selfie')
  ) then raise exception 'لا يمكن قبول المندوب قبل اكتمال صور الهوية والسيلفي'; end if;
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
revoke all on function public.restaurant_review_courier_application(uuid,text,text) from public,anon;
grant execute on function public.restaurant_review_courier_application(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
