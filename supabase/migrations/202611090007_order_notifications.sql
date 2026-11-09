-- Notify customers and restaurant staff when an order is created or changes state.
begin;

create or replace function public.notify_saree_order_events()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  status_title text;
  status_body text;
begin
  if tg_op = 'INSERT' then
    insert into public.notifications(user_id, title, body, kind, related_order_id)
    select rm.user_id,
           'طلب جديد',
           'وصل طلب جديد رقم #' || new.order_number || ' إلى مطعمكم.',
           'new_order',
           new.id
    from public.restaurant_members rm
    where rm.restaurant_id = new.restaurant_id;

    return new;
  end if;

  if new.status is distinct from old.status then
    status_title := case new.status
      when 'accepted' then 'تم قبول طلبك'
      when 'preparing' then 'بدأ تحضير طلبك'
      when 'ready_for_pickup' then 'طلبك جاهز'
      when 'assigned' then 'تم تعيين مندوب'
      when 'picked_up' then 'طلبك في الطريق'
      when 'delivered' then 'تم توصيل طلبك'
      when 'cancelled' then 'تم إلغاء الطلب'
      else 'تحديث الطلب'
    end;
    status_body := 'تم تحديث حالة الطلب رقم #' || new.order_number || '.';
    insert into public.notifications(user_id, title, body, kind, related_order_id)
    values (new.customer_id, status_title, status_body, 'order_status', new.id);
  end if;

  if new.courier_id is distinct from old.courier_id and new.courier_id is not null then
    insert into public.notifications(user_id, title, body, kind, related_order_id)
    values (new.courier_id, 'تم إسناد طلب إليك', 'لديك طلب توصيل جديد رقم #' || new.order_number || '.', 'delivery_assigned', new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists orders_notify_saree_events on public.orders;
create trigger orders_notify_saree_events
after insert or update of status, courier_id on public.orders
for each row execute function public.notify_saree_order_events();

revoke all on function public.notify_saree_order_events() from public, anon, authenticated;
grant execute on function public.notify_saree_order_events() to service_role;

commit;