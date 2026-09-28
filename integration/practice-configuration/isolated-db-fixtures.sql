-- Run only against a disposable PracticeCtrl development database with V1 applied.
-- Every fixture is synthetic; the transaction rolls back even when all assertions pass.
begin;

insert into auth.users(id,email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','practice-a@example.invalid'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','practice-b@example.invalid'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','reception-a@example.invalid');
insert into public.practice(id,name,tenant_slug) values
 ('aaaaaaaa-0000-4000-8000-000000000001','Synthetic A','synthetic-a-audit'),
 ('bbbbbbbb-0000-4000-8000-000000000002','Synthetic B','synthetic-b-audit');
insert into public.practice_staff_member(practice_id,user_id,role) values
 ('aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','practice_manager'),
 ('bbbbbbbb-0000-4000-8000-000000000002','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','practice_manager'),
 ('aaaaaaaa-0000-4000-8000-000000000001','dddddddd-dddd-4ddd-8ddd-dddddddddddd','reception');
insert into public.medical_scheme(id,name) values
 ('cccccccc-0000-4000-8000-000000000003','Synthetic scheme');
insert into public.practice_operating_config(practice_id) values
 ('bbbbbbbb-0000-4000-8000-000000000002');
insert into public.practice_payer_relationship(practice_id,medical_scheme_id,relationship_type,effective_from) values
 ('aaaaaaaa-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000003','unknown','2026-01-01'),
 ('bbbbbbbb-0000-4000-8000-000000000002','cccccccc-0000-4000-8000-000000000003','unknown','2026-01-01');
insert into public.payer_billing_rule(id,practice_id,rule_scope,rule_type,code_system,code,calculation_method,fixed_amount,effective_from,effective_to,version,status) values
 ('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001','practice_contract','tariff','CPT','0190','fixed_amount',1146,'2026-01-01','2026-12-31',1,'active'),
 ('aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001','practice_contract','tariff','CPT','0190','fixed_amount',1210,'2027-01-01',null,2,'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","aal":"aal2","role":"authenticated"}';
insert into public.practice_operating_config(practice_id) values
 ('aaaaaaaa-0000-4000-8000-000000000001');
insert into public.practice_policy(practice_id,policy_key,title,category,sop,effective_from)
 values ('aaaaaaaa-0000-4000-8000-000000000001','synthetic_authorisation','Synthetic authorisation','Authorisations','Review first','2026-01-01');
update public.practice_policy set status='in_review' where policy_key='synthetic_authorisation';
update public.practice_policy set status='approved',approved_by=auth.uid(),approved_at=now() where policy_key='synthetic_authorisation';
do $$
declare december jsonb; january jsonb;
begin
 if (select count(*) from public.practice_operating_config) <> 1 then raise exception 'Operating configuration tenant read failed'; end if;
 if (select count(*) from public.practice_payer_relationship) <> 1 then raise exception 'Payer relationship tenant read failed'; end if;
 if exists(select 1 from public.practice_operating_config where practice_id='bbbbbbbb-0000-4000-8000-000000000002') then raise exception 'Cross-tenant read leaked'; end if;
 update public.practice_operating_config set cancellation_notice_hours=8 where practice_id='bbbbbbbb-0000-4000-8000-000000000002';
 if found then raise exception 'Cross-tenant update permitted'; end if;
 if not exists(select 1 from public.practice_configuration_event where practice_id='aaaaaaaa-0000-4000-8000-000000000001' and entity_type='practice_operating_config' and action='INSERT' and actor_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then raise exception 'Audit actor missing'; end if;
 december:=public.simulate_practice_payer_rule('aaaaaaaa-0000-4000-8000-000000000001',null,null,null,'CPT','0190','2026-12-15',1000,1450,1);
 january:=public.simulate_practice_payer_rule('aaaaaaaa-0000-4000-8000-000000000001',null,null,null,'CPT','0190','2027-01-15',1000,1450,1);
 if (december->>'expected_scheme_amount')::numeric <> 1146 or (january->>'expected_scheme_amount')::numeric <> 1210 then raise exception 'Service-date amounts wrong'; end if;
 if (december->'decision_trace'->>'rule_version')::int <> 1 or (january->'decision_trace'->>'rule_version')::int <> 2 then raise exception 'Historical provenance wrong'; end if;
 begin
  perform public.simulate_practice_payer_rule('bbbbbbbb-0000-4000-8000-000000000002',null,null,null,'CPT','0190','2026-12-15',1000,1450,1);
  raise exception 'Cross-tenant simulation permitted';
 exception when others then
  if sqlerrm <> 'Practice access required' then raise; end if;
 end;
 begin
  update public.practice_policy set status='active' where policy_key='synthetic_authorisation';
  raise exception 'Non-executable policy activated';
 exception when others then
  if sqlerrm <> 'Policy execution is not connected to Operations; keep the approved policy inactive' then raise; end if;
 end;
end $$;

set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","aal":"aal1","role":"authenticated"}';
do $$ begin
 update public.practice_operating_config set cancellation_notice_hours=8 where practice_id='aaaaaaaa-0000-4000-8000-000000000001';
 if found then raise exception 'AAL1 manager update permitted'; end if;
end $$;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","aal":"aal2","role":"authenticated"}';
do $$ begin
 update public.practice_operating_config set cancellation_notice_hours=8 where practice_id='aaaaaaaa-0000-4000-8000-000000000001';
 if found then raise exception 'Reception update permitted'; end if;
end $$;

rollback;
