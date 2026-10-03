-- Synthetic full claim-preflight verification.
-- Run only against a disposable PracticeCtrl development database.
-- All fixture data rolls back.
--
-- Verifies:
-- * governed licensed SAMA CCSA source provenance
-- * verified patient scheme membership
-- * active payer contract + effective tariff rule
-- * claim-eligible clinical invoice-line creation
-- * automatic payer resolution
-- * full claim preflight ready state
-- * persisted rule/contract provenance and audit event

begin;

insert into auth.users(id,email) values
 ('44444444-4444-4444-8444-444444444444','claim-manager@example.invalid');

insert into public.practice(id,name,tenant_slug) values
 ('44444444-0000-4000-8000-000000000001','Claim Test Practice','claim-test-practice');

insert into public.practice_staff_member(practice_id,user_id,role) values
 ('44444444-0000-4000-8000-000000000001','44444444-4444-4444-8444-444444444444','practice_manager');

insert into public.crm_patient(id,practice_id,display_name) values
 ('44444444-0000-4000-8000-000000000002','44444444-0000-4000-8000-000000000001','Synthetic Claim Patient');

insert into public.integration_provider(
 id,slug,name,provider_type,authoritative_for,commercial_agreement_required,lifecycle_status
) values (
 '44444444-0000-4000-8000-000000000010','synthetic-ccsa-fixture','Synthetic CCSA Fixture',
 'coding_licensor',array['billing_codes'],true,'active'
);

insert into public.source_dataset(
 id,provider_id,dataset_key,name,domain,authority_level,access_model,
 licence_required,versioned_required,provenance_required,effective_dating_required,status
) values (
 '44444444-0000-4000-8000-000000000011','44444444-0000-4000-8000-000000000010',
 'synthetic_ccsa_fixture','Synthetic licensed CCSA fixture','billing','licensed','licensed_file',
 true,true,true,true,'active'
);

insert into public.source_dataset_release(
 id,dataset_id,release_name,version,published_date,effective_from,retrieved_at,
 licence_reference,status
) values (
 '44444444-0000-4000-8000-000000000012','44444444-0000-4000-8000-000000000011',
 'Synthetic CCSA 2026','2026-test','2026-01-01','2026-01-01',now(),
 'SYNTHETIC-TEST-LICENCE','pending_review'
);

insert into public.source_file(
 id,dataset_id,source_release_id,object_path,original_filename,mime_type,byte_size,
 sha256,uploaded_by,status,source_uri
) values (
 '44444444-0000-4000-8000-000000000014','44444444-0000-4000-8000-000000000011',
 '44444444-0000-4000-8000-000000000012','fixtures/synthetic-ccsa-2026.csv',
 'synthetic-ccsa-2026.csv','text/csv',128,
 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '44444444-4444-4444-8444-444444444444','registered','synthetic://ccsa-fixture'
);

update public.source_dataset_release
set source_file_id='44444444-0000-4000-8000-000000000014',
    content_sha256='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    source_uri='synthetic://ccsa-fixture',
    status='active',
    activated_by='44444444-4444-4444-8444-444444444444'
where id='44444444-0000-4000-8000-000000000012';

insert into public.billing_code_reference(
 id,code_system,code,description,source_release_id,effective_from,active
) values (
 '44444444-0000-4000-8000-000000000013','SAMA_CCSA','0190',
 'Synthetic consultation code for rollback fixture',
 '44444444-0000-4000-8000-000000000012','2026-01-01',true
);

insert into public.medical_scheme(id,name) values
 ('44444444-0000-4000-8000-000000000020','Synthetic Scheme');

insert into public.crm_patient_scheme_membership(
 id,practice_id,patient_id,medical_scheme_id,scheme_name_snapshot,
 member_number_masked,member_number_secret_id,membership_status,effective_from,
 verification_source,verified_at
) values (
 '44444444-0000-4000-8000-000000000021','44444444-0000-4000-8000-000000000001',
 '44444444-0000-4000-8000-000000000002','44444444-0000-4000-8000-000000000020',
 'Synthetic Scheme','****1234','44444444-0000-4000-8000-000000000022',
 'active_verified','2026-01-01','synthetic_test',now()
);

insert into public.payer_contract(
 id,practice_id,medical_scheme_id,agreement_type,contract_reference,effective_from,status
) values (
 '44444444-0000-4000-8000-000000000030','44444444-0000-4000-8000-000000000001',
 '44444444-0000-4000-8000-000000000020','network','SYNTH-CLAIM-2026','2026-01-01','active'
);

insert into public.payer_billing_rule(
 id,practice_id,contract_id,medical_scheme_id,rule_scope,rule_type,code_system,code,
 calculation_method,fixed_amount,effective_from,status
) values (
 '44444444-0000-4000-8000-000000000031','44444444-0000-4000-8000-000000000001',
 '44444444-0000-4000-8000-000000000030','44444444-0000-4000-8000-000000000020',
 'practice_contract','tariff','SAMA_CCSA','0190','fixed_amount',1146,'2026-01-01','active'
);

insert into public.billing_invoice(
 id,practice_id,patient_id,invoice_number,invoice_date,medical_scheme_id,payer_contract_id,
 status,total_amount,scheme_portion,patient_portion,balance_amount
) values (
 '44444444-0000-4000-8000-000000000040','44444444-0000-4000-8000-000000000001',
 '44444444-0000-4000-8000-000000000002','TEST-CLAIM-INV-1','2026-10-03',
 '44444444-0000-4000-8000-000000000020','44444444-0000-4000-8000-000000000030',
 'draft',0,0,0,0
);

set local role authenticated;
set local request.jwt.claims =
 '{"sub":"44444444-4444-4444-8444-444444444444","aal":"aal2","role":"authenticated"}';

do $$
declare
  line_id uuid;
  preflight jsonb;
begin
  line_id := public.add_revenue_invoice_line(
    '44444444-0000-4000-8000-000000000040',
    'clinical','Synthetic claim-eligible consultation',1,1450,'2026-10-03',
    'SAMA_CCSA','0190','{}'::text[],array['Z00.0'],0,true
  );

  if line_id is null then raise exception 'Claim-eligible line was not created'; end if;

  perform set_config('practicectrl.billing_line_mutation','on',true);
  update public.billing_invoice_line set reference_amount=1000 where id=line_id;
  perform set_config('practicectrl.billing_line_mutation','off',true);

  preflight := public.run_invoice_claim_preflight(
    '44444444-0000-4000-8000-000000000040',true
  );

  if preflight->>'status'<>'ready'
     or coalesce((preflight->>'blocking_count')::int,-1)<>0 then
    raise exception 'Expected ready claim preflight, got %',preflight;
  end if;

  if coalesce((preflight->>'verified_membership_active')::boolean,false) is not true then
    raise exception 'Verified membership was not recognised';
  end if;

  if not exists(
    select 1 from public.billing_invoice_line l
    where l.id=line_id
      and l.payer_rule_resolution_id is not null
      and l.expected_scheme_amount=1146
      and l.expected_patient_liability=304
  ) then
    raise exception 'Payer resolution was not persisted to the claim line';
  end if;

  if not exists(
    select 1 from public.billing_invoice_event
    where invoice_id='44444444-0000-4000-8000-000000000040'
      and event_type='validated'
      and metadata->>'validation'='payer_claim_preflight'
      and metadata->>'status'='ready'
  ) then
    raise exception 'Ready preflight audit event missing';
  end if;
end $$;

rollback;
