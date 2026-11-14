-- Make courier residence proof optional and require a live selfie holding the ID.
begin;

create or replace function public.admin_review_user(p_user_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare target_role text;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'متاح للمدير فقط'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'قرار اعتماد غير صالح'; end if;
  select role into target_role from public.profiles where id = p_user_id for update;
  if not found then raise exception 'الحساب غير موجود'; end if;
  if target_role in ('customer','admin') then raise exception 'هذا الحساب لا يحتاج اعتماداً'; end if;
  if target_role = 'courier' and p_decision = 'approved' and (
    select count(distinct d.document_type)
    from public.courier_verification_documents d
    join storage.objects o
      on o.bucket_id = 'courier-verification'
     and o.name = d.storage_path
    where d.courier_id = p_user_id
      and d.storage_path like p_user_id::text || '/%'
      and d.document_type in ('id_front','id_back','selfie')
  ) <> 3 then
    raise exception 'لا يمكن اعتماد المندوب قبل استلام صورة الهوية الأمامية والخلفية والسيلفي مع البطاقة';
  end if;
  update public.profiles
  set approval_status = p_decision,
      approved_at = case when p_decision = 'approved' then now() else null end,
      approval_note = nullif(trim(coalesce(p_note,'')), '')
  where id = p_user_id;
end;
$$;

revoke all on function public.admin_review_user(uuid,text,text) from public, anon;
grant execute on function public.admin_review_user(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;
