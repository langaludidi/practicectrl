-- Synthetic practitioner-only Clinical boundary regression.
-- Run only against a disposable PracticeCtrl development database.
-- All fixture data rolls back.

begin;

insert into auth.users(id,email) values
 ('77777777-7777-4777-8777-777777777771','privacy3-practitioner@example.invalid'),
 ('77777777-7777-4777-8777-777777777772','privacy3-clinical-admin@example.invalid');

insert into public.practice(id,name,tenant_slug) values
 ('77777777-0000-4000-8000-000000000001','Privacy Phase 3 Practice','privacy-phase3');

insert into public.practice_staff_member(practice_id,user_id,role) values
 ('77777777-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777771','practitioner'),
 ('77777777-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777772','clinical_admin');

insert into public.crm_patient(id,practice_id,display_name) values
 ('77777777-0000-4000-8000-000000000010','77777777-0000-4000-8000-000000000001','Synthetic Clinical Patient');

insert into public.integration_provider(
 id,slug,name,provider_type,authoritative_for,lifecycle_status
) values (
 '77777777-0000-4000-8000-000000000020','synthetic-pathology-phase3','Synthetic Pathology Phase 3',
 'pathology_lab',array['pathology'],'active'
);

set local role authenticated;
set local request.jwt.claims =
 '{"sub":"77777777-7777-4777-8777-777777777772","aal":"aal2","role":"authenticated"}';

do $$
begin
  begin
    insert into public.patient_allergy(practice_id,patient_id,substance_text,severity,recorded_by)
    values (
      '77777777-0000-4000-8000-000000000001','77777777-0000-4000-8000-000000000010',
      'Clinical admin should not create','moderate','77777777-7777-4777-8777-777777777772'
    );
    raise exception 'Clinical admin inserted patient allergy';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.pathology_order(
      practice_id,patient_id,provider_id,order_number,clinical_indication,treating_practitioner_user_id,created_by
    ) values (
      '77777777-0000-4000-8000-000000000001','77777777-0000-4000-8000-000000000010',
      '77777777-0000-4000-8000-000000000020','SHOULD-NOT-CREATE',
      'Clinical admin should not create',null,'77777777-7777-4777-8777-777777777772'
    );
    raise exception 'Clinical admin inserted pathology order';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.record_patient_medication(
      '77777777-0000-4000-8000-000000000001',
      '77777777-0000-4000-8000-000000000010',
      null,null,'Clinical admin medicine',null,null,null,null,current_date,'clinical'
    );
    raise exception 'Clinical admin RPC created patient medication';
  exception when others then
    if sqlerrm like '%Clinical admin RPC created%' then raise; end if;
  end;
end $$;

set local request.jwt.claims =
 '{"sub":"77777777-7777-4777-8777-777777777771","aal":"aal2","role":"authenticated"}';

insert into public.patient_allergy(practice_id,patient_id,substance_text,severity,recorded_by)
values (
  '77777777-0000-4000-8000-000000000001','77777777-0000-4000-8000-000000000010',
  'Practitioner allergen','moderate','77777777-7777-4777-8777-777777777771'
);

insert into public.pathology_order(
  practice_id,patient_id,provider_id,order_number,clinical_indication,treating_practitioner_user_id,created_by
) values (
  '77777777-0000-4000-8000-000000000001','77777777-0000-4000-8000-000000000010',
  '77777777-0000-4000-8000-000000000020','PRACTITIONER-CREATE',
  'Practitioner clinical indication','77777777-7777-4777-8777-777777777771',
  '77777777-7777-4777-8777-777777777771'
);

do $$
begin
  if (select count(*) from public.patient_allergy
      where practice_id='77777777-0000-4000-8000-000000000001')<>1 then
    raise exception 'Practitioner allergy write/read failed';
  end if;
  if (select count(*) from public.pathology_order
      where practice_id='77777777-0000-4000-8000-000000000001')<>1 then
    raise exception 'Practitioner pathology write/read failed';
  end if;
end $$;

rollback;
