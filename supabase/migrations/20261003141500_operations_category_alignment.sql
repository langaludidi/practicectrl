begin;

alter table public.operations_work_item
  drop constraint if exists operations_work_item_category_check;

alter table public.operations_work_item
  add constraint operations_work_item_category_check
  check (
    category = any(array[
      'appointment_request','patient_follow_up','documentation','coding','billing','claim',
      'revenue','revenue_integrity','communication','referral','compliance','pathology','other'
    ]::text[])
  );

commit;
