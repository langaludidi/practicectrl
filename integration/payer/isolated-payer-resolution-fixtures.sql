-- Synthetic payer-foundation verification.
-- Run only against a disposable PracticeCtrl development database.
-- This test rolls back all fixture data.
--
-- Scope:
-- * recovered payer contract/rule tables
-- * invoice -> selected payer contract linkage
-- * service-date contract simulation
-- * invoice-line payer preview
-- * governed payer-resolution recording
-- * expected scheme/patient split and provenance
--
-- This is not a full claim-preflight test. Claim-eligible production coding still
-- requires the governed licensed SAMA CCSA source and verified membership path.

begin;

insert into auth.users(id,email) values
 ('33333333-3333-4333-8333-333333333333','payer-manager@example.invalid');

insert into public.practice(id,name,tenant_slug) values
 ('33333333-0000-4000-8000-000000000001','Payer Test Practice','payer-test-practice');

insert into public.practice_staff_member(practice_id,user_id,role) values
 ('33333333-0000-4000-8000-000000000001','33333333-3333-4333-8333-333333333333','practice_manager');

insert into public.medical_scheme(id,name) values
 ('33333333-0000-4000-8000-000000000010','Synthetic Payer');

insert into public.payer_contract(
 id,practice_id,medical_scheme_id,agreement_type,contract_reference,effective_from,status
) values (
 '33333333-0000-4000-8000-000000000030','33333333-0000-4000-8000-000000000001',
 '33333333-0000-4000-8000-000000000010','network','SYNTH-2026','2026-01-01','active'
);

insert into public.payer_billing_rule(
 id,practice_id,contract_id,medical_scheme_id,rule_scope,rule_type,code_system,code,
 calculation_method,fixed_amount,effective_from,status
) values (
 '33333333-0000-4000-8000-000000000031','33333333-0000-4000-8000-000000000001',
 '33333333-0000-4000-8000-000000000030','33333333-0000-4000-8000-000000000010',
 'practice_contract','tariff','PRACTICE_CUSTOM','0190','fixed_amount',1146,'2026-01-01','active'
);

insert into public.billing_invoice(
 id,practice_id,invoice_number,invoice_date,medical_scheme_id,payer_contract_id,status,
 total_amount,scheme_portion,patient_portion,balance_amount
) values (
 '33333333-0000-4000-8000-000000000020','33333333-0000-4000-8000-000000000001',
 'TEST-INV-1','2026-10-03','33333333-0000-4000-8000-000000000010',
 '33333333-0000-4000-8000-000000000030','draft',1450,0,0,1450
);

insert into public.billing_invoice_line(
 id,invoice_id,line_no,code_system,code,description_snapshot,quantity,unit_amount,
 line_amount,service_date,claim_eligible
) values (
 '33333333-0000-4000-8000-000000000021','33333333-0000-4000-8000-000000000020',
 1,'PRACTICE_CUSTOM','0190','Synthetic consultation',1,1450,1450,'2026-10-03',true
);

set local role authenticated;
set local request.jwt.claims =
 '{"sub":"33333333-3333-4333-8333-333333333333","aal":"aal2","role":"authenticated"}';

do $$
declare
  simulation jsonb;
  preview jsonb;
  resolution_id uuid;
  expected numeric;
begin
  simulation := public.simulate_payer_contract_payment(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000030',
    null,'PRACTICE_CUSTOM','0190','2026-10-03',1000,1450,1,'{}'
  );

  if coalesce((simulation->>'expected_scheme_amount')::numeric,-1) <> 1146 then
    raise exception 'Contract simulator amount mismatch: %', simulation;
  end if;

  preview := public.preview_invoice_line_payer_resolution(
    '33333333-0000-4000-8000-000000000021',null,1000
  );

  if coalesce((preview->>'matched')::boolean,false) is not true
     or coalesce((preview->>'expected_scheme_amount')::numeric,-1) <> 1146
     or coalesce((preview->>'estimated_patient_liability')::numeric,-1) <> 304 then
    raise exception 'Invoice payer preview mismatch: %', preview;
  end if;

  resolution_id := public.record_invoice_line_payer_resolution(
    '33333333-0000-4000-8000-000000000021',null,1000
  );

  if resolution_id is null then
    raise exception 'Resolution was not recorded';
  end if;

  select expected_scheme_amount
  into expected
  from public.billing_invoice_line
  where id='33333333-0000-4000-8000-000000000021';

  if expected <> 1146 then
    raise exception 'Invoice line resolution did not persist expected scheme amount';
  end if;

  if not exists(
    select 1
    from public.payer_rule_resolution
    where id=resolution_id
      and applied_contract_id='33333333-0000-4000-8000-000000000030'
      and applied_rule_id='33333333-0000-4000-8000-000000000031'
      and expected_patient_liability=304
  ) then
    raise exception 'Resolution provenance missing or incorrect';
  end if;
end $$;

rollback;
