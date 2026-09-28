drop policy if exists billing_receipt_finance_update on public.billing_payment_receipt;
create policy billing_receipt_finance_update on public.billing_payment_receipt
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
);
