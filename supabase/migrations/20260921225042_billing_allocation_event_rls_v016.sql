drop policy if exists billing_allocation_event_finance_insert on public.billing_allocation_event;
create policy billing_allocation_event_finance_insert on public.billing_allocation_event
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and actor_user_id=(select auth.uid())
  and exists(
    select 1
    from public.billing_payment_allocation a
    join public.billing_payment_receipt r on r.id=a.receipt_id
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where a.id=billing_allocation_event.allocation_id
      and m.user_id=(select auth.uid())
      and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
