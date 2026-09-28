
begin;

-- Reconcile exploratory seed data into migration history so staging is reproducible.

insert into public.practice_payer_priority_snapshot
(practice_id,snapshot_date,source_label,payer_label,patient_count,rank,notes)
select p.id, date '2026-08-25',
       'VeriClaim Total Patients per Scheme per Option — generated 2026-08-25',
       x.payer_label,x.patient_count,x.rank,x.notes
from public.practice p
cross join (values
 ('GEMS',2080,1,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('DISCOVERY HEALTH',1599,2,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('BONITAS',1019,3,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('SIZWE / SIZWE HOSMED',737,4,'Includes legacy Sizwe and current Sizwe Hosmed-labelled rows; use only as prioritisation, not current regulatory truth.'),
 ('POLMED',657,5,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('LA HEALTH',394,6,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('MEDIMED',359,7,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('MEDSHIELD',267,8,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('BESTMED',212,9,'Historical option-level rows aggregated to scheme family for integration prioritisation.'),
 ('MALCOR / TOTAL MED',159,10,'Historical source label retained; canonical CMS mapping still required.')
) as x(payer_label,patient_count,rank,notes)
where p.name='Dr Tembisa Tini Inc'
on conflict (practice_id,snapshot_date,payer_label) do update set
  patient_count=excluded.patient_count,
  rank=excluded.rank,
  source_label=excluded.source_label,
  notes=excluded.notes;

insert into public.billing_code_system(code,display_name,code_domain,owner_provider_id,licence_required,notes)
select 'SA_ICD10','South African ICD-10','diagnosis',id,false,
       'Code10 authority remains public.sa_icd10_code; this identifier is used by billing/claim lines.'
from public.integration_provider where slug='ndoh'
on conflict (code) do update set
  display_name=excluded.display_name,
  owner_provider_id=excluded.owner_provider_id,
  licence_required=excluded.licence_required,
  notes=excluded.notes;

insert into public.billing_code_system(code,display_name,code_domain,owner_provider_id,licence_required,notes)
select 'SAMA_CCSA','SAMA CCSA','procedure',id,true,
       'Licensed procedure-code content. Do not populate until PracticeCtrl has appropriate data-use rights.'
from public.integration_provider where slug='sama'
on conflict (code) do update set
  display_name=excluded.display_name,
  owner_provider_id=excluded.owner_provider_id,
  licence_required=excluded.licence_required,
  notes=excluded.notes;

insert into public.billing_code_system(code,display_name,code_domain,owner_provider_id,licence_required,notes)
select 'NAPPI','NAPPI','product',id,true,
       'MediKredit-owned product coding/price data. Do not populate licensed content without agreement.'
from public.integration_provider where slug='medikredit'
on conflict (code) do update set
  display_name=excluded.display_name,
  owner_provider_id=excluded.owner_provider_id,
  licence_required=excluded.licence_required,
  notes=excluded.notes;

insert into public.billing_code_system(code,display_name,code_domain,owner_provider_id,licence_required,notes)
values ('PRACTICE_CUSTOM','Practice-defined billing code','other',null,false,
        'Local code namespace; cannot masquerade as an external coding authority.')
on conflict (code) do nothing;

insert into public.source_dataset_release
(dataset_id,release_name,version,published_date,effective_from,source_uri,status,notes)
select d.id,'Registered medical schemes - 2026','Circular 12 of 2026','2026-04-16','2026-01-01',
       'https://www.medicalschemes.co.za/latest-publication/circular-12-of-2026-notification-of-registration-of-medical-schemes/',
       'pending_review',
       'CMS confirms the medical schemes registered for the 2026 calendar year. Exact source list/file must be hashed and validated before activation.'
from public.source_dataset d where d.dataset_key='cms_schemes_2026'
  and not exists (
    select 1 from public.source_dataset_release r
    where r.dataset_id=d.id and r.release_name='Registered medical schemes - 2026'
  );

insert into public.source_dataset_release
(dataset_id,release_name,version,published_date,effective_from,source_uri,status,notes)
select d.id,'Approved benefit options - 2026','Circular 41 of 2025','2025-12-12','2026-01-01',
       'https://www.medicalschemes.co.za/latest-publication/circular-41-of-2025-open-and-restricted-medical-schemes-approved-benefit-options-and-contribution-adjustments/',
       'pending_review',
       'CMS approved benefit-option status for the 2026 benefit year. Exact circular file must be hashed and parsed before activation.'
from public.source_dataset d where d.dataset_key='cms_benefit_options_2026'
  and not exists (
    select 1 from public.source_dataset_release r
    where r.dataset_id=d.id and r.release_name='Approved benefit options - 2026'
  );

insert into public.source_dataset_release
(dataset_id,release_name,version,published_date,effective_from,source_uri,status,notes)
select d.id,'2026 PMB ICD-10 Coded List','2026 distribution 4','2026-05-08','2026-01-01',
       'https://www.medicalschemes.co.za/wpfd_file/2026-pmb-icd-10-coded-list-distribution-4/',
       'pending_review',
       'PMB coded-list guidance only. File hash, schema validation and clinical-review semantics are required before activation.'
from public.source_dataset d where d.dataset_key='cms_pmb_icd10_2026'
  and not exists (
    select 1 from public.source_dataset_release r
    where r.dataset_id=d.id and r.release_name='2026 PMB ICD-10 Coded List'
  );

insert into public.source_dataset_release
(dataset_id,release_name,version,published_date,effective_from,source_uri,status,notes)
select d.id,'South African ICD-10 Master Industry Table 2021','2021',null,null,
       'https://www.health.gov.za/icd-10-master-industry-table/',
       'pending_review',
       'NDoH MIT public source. Exact workbook hash and 24-column schema validation are required before Code10 activation.'
from public.source_dataset d where d.dataset_key='sa_icd10_mit'
  and not exists (
    select 1 from public.source_dataset_release r
    where r.dataset_id=d.id and r.release_name='South African ICD-10 Master Industry Table 2021'
  );

commit;
