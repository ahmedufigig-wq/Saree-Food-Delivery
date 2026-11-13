-- Activate or suspend restaurant team access when administration reviews a courier.
create or replace function public.sync_restaurant_courier_approval()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.restaurant_couriers
     set is_active = (new.approval_status = 'approved' and not new.is_blocked),
         updated_at = now()
   where courier_id = new.id;
  return new;
end;
$$;

drop trigger if exists trg_sync_restaurant_courier_approval on public.profiles;
create trigger trg_sync_restaurant_courier_approval
after update of approval_status, is_blocked on public.profiles
for each row
when (
  old.approval_status is distinct from new.approval_status
  or old.is_blocked is distinct from new.is_blocked
)
execute function public.sync_restaurant_courier_approval();
