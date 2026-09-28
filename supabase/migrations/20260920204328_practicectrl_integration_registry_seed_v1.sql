
begin;

insert into public.platform_module
(module_key,display_name,descriptor,flagship,enabled_by_default,ai_enabled,voice_enabled,status)
values
('code10','Code10','Clinical Coding Intelligence',true,true,true,true,'development'),
('crm','CRM','Patient relationships, referrals, communications and follow-up',false,false,true,true,'foundation'),
('billing','Billing & Invoicing','Patient and scheme billing, invoices, statements and receipts',false,false,true,true,'planned'),
('claims_revenue','Claims & Revenue Integrity','Claims, responses, eRA, reconciliation and recovery',false,false,true,true,'planned'),
('communications','Communications','Email, messaging, templates, consent and communication history',false,false,true,true,'planned'),
('operations','Practice Operations','Work queues, tasks, accountability, exceptions and SLA monitoring',false,false,true,true,'planned'),
('analytics','Analytics & Reporting','Clinical, coding, financial and operational intelligence',false,false,true,true,'planned'),
('admin','Administration & Compliance','Users, roles, audit, privacy, sources and integration governance',false,true,true,true,'foundation')
on conflict (module_key) do update set
  display_name=excluded.display_name,
  descriptor=excluded.descriptor,
  flagship=excluded.flagship,
  enabled_by_default=excluded.enabled_by_default,
  ai_enabled=excluded.ai_enabled,
  voice_enabled=excluded.voice_enabled,
  status=excluded.status;

insert into public.practice_module(practice_id,module_id,enabled,enabled_at)
select p.id,m.id,
       case when m.module_key in ('code10','crm','admin') then true else false end,
       case when m.module_key in ('code10','crm','admin') then now() else null end
from public.practice p
cross join public.platform_module m
where p.name='Dr Tembisa Tini Inc'
on conflict (practice_id,module_id) do nothing;

insert into public.integration_capability_catalog
(code,display_name,domain,description,requires_patient_context,transactional)
values
('icd10_reference','ICD-10 reference','coding','South African ICD-10 code authority/reference',false,false),
('icd10_rules','ICD-10 coding rules','coding','South African coding standards, addenda and validation rules',false,false),
('procedure_codes','Procedure codes','coding','Procedure/service code content and modifiers',false,false),
('pmb_guidance','PMB guidance','coding','PMB coded-list and descriptor intelligence',false,false),
('scheme_registry','Medical scheme registry','payer','Registered medical scheme identity/status',false,false),
('benefit_options_directory','Benefit options directory','payer','Approved scheme benefit options and annual status',false,false),
('member_validation','Member status validation','payer','Validate member/dependant details and membership status',true,true),
('family_validation','Family/dependant validation','payer','Retrieve/validate family or dependant membership profile',true,true),
('benefit_check','Benefit checking','payer','Check available benefits/quote response before treatment',true,true),
('claim_submit','Claim submission','claims','Submit medical scheme claims electronically',true,true),
('claim_response','Claim response','claims','Receive claim acknowledgements, adjudication or rejection responses',true,true),
('claim_amend','Claim amendment/resubmission','claims','Amend/re-submit previously submitted claims',true,true),
('claim_reverse','Claim reversal','claims','Reverse submitted claims where supported',true,true),
('era_receive','Electronic remittance advice','revenue','Receive funder/administrator electronic remittance advice',true,true),
('era_reconcile','ERA reconciliation','revenue','Match remittance lines to claims/payments and surface exceptions',true,true),
('payer_rule_validation','Payer rule validation','claims','Validate claims against payer-specific processing rules',true,true),
('tariff_reference','Tariff/rate reference','billing','Effective-dated scheme/contract pricing or rate data',false,false),
('nappi_product_file','NAPPI product/price file','coding','Pharmaceutical/device/consumable identifiers and product/price data',false,false),
('preauthorisation','Pre-authorisation','claims','Request or track authorisation where supported',true,true)
on conflict (code) do update set
  display_name=excluded.display_name,
  domain=excluded.domain,
  description=excluded.description,
  requires_patient_context=excluded.requires_patient_context,
  transactional=excluded.transactional;

insert into public.integration_provider
(slug,name,provider_type,website_url,authoritative_for,commercial_agreement_required,accreditation_required,lifecycle_status,notes,last_verified_at)
values
('ndoh','National Department of Health','coding_authority','https://www.health.gov.za/icd-10-master-industry-table/',
 array['South African ICD-10 Master Industry Table'],false,false,'active',
 'Canonical South African ICD-10 source layer for PracticeCtrl Code10.',now()),
('phisc','Private Healthcare Information Standards Committee','standards_body','https://www.phisc.net/standards/phisc-standards',
 array['South African ICD-10 implementation addenda','CCSA coding standards and guidelines'],false,false,'active',
 'Industry implementation standards/guidance; not legislation.',now()),
('cms','Council for Medical Schemes','regulator','https://www.medicalschemes.co.za/',
 array['Registered medical schemes','Approved benefit options','PMB guidance'],false,false,'active',
 'Regulatory/public-information source. Transactional member/benefit data must come from authorised payer/switch channels.',now()),
('sama','South African Medical Association','coding_licensor','https://samedical.org/',
 array['Medical Doctors Coding Manual','CCSA procedure coding content'],true,false,'contact_required',
 'Procedure-code content is licensed/copyrighted; PracticeCtrl requires a legitimate commercial data arrangement.',now()),
('medikredit','MediKredit Integrated Healthcare Solutions','claims_switch','https://www.medikredit.co.za/',
 array['Claims switching','Electronic remittance advice','NAPPI'],true,true,'contact_required',
 'Publicly documents PMS-vendor accreditation against specified data-file layouts and HealthNet ST synchronous/asynchronous switching.',now()),
('altron-switchon','Altron HealthTech SwitchOn','claims_switch','https://healthtech.altron.com/product-switchon',
 array['Claims switching','Member validation','Benefit checking','Electronic remittance advice'],true,false,'contact_required',
 'Public product information confirms transaction capabilities; technical third-party integration specification still required.',now()),
('healthbridge','Healthbridge','claims_switch','https://healthbridge.co.za/',
 array['Claims processing','Electronic remittance workflows','Practice billing'],true,false,'research',
 'Public material confirms capabilities in Healthbridge products; third-party PracticeCtrl integration availability is not yet confirmed.',now())
on conflict (slug) do update set
  name=excluded.name,
  provider_type=excluded.provider_type,
  website_url=excluded.website_url,
  authoritative_for=excluded.authoritative_for,
  commercial_agreement_required=excluded.commercial_agreement_required,
  accreditation_required=excluded.accreditation_required,
  lifecycle_status=excluded.lifecycle_status,
  notes=excluded.notes,
  last_verified_at=excluded.last_verified_at;

-- Interfaces: intentionally avoid inventing API endpoints or auth schemes.
insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,specification_reference,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'NDoH published ICD-10 downloads','manual_download','inbound','manual',
       'https://www.health.gov.za/icd-10-master-industry-table/',null,false,false,false,'active',
       'Versioned source acquisition; original files must be hashed and retained.'
from public.integration_provider where slug='ndoh'
on conflict (provider_id,name) do nothing;

insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'PHISC published standards','manual_download','inbound','manual',
       'https://www.phisc.net/standards/phisc-standards',false,false,false,'active',
       'Published addenda/standards ingested as governed rule sources.'
from public.integration_provider where slug='phisc'
on conflict (provider_id,name) do nothing;

insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'CMS published regulatory datasets','manual_download','inbound','manual',
       'https://www.medicalschemes.co.za/',false,false,false,'active',
       'Registered schemes, benefit options and PMB guidance are versioned separately.'
from public.integration_provider where slug='cms'
on conflict (provider_id,name) do nothing;

insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'SAMA licensed coding content','licensed_dataset','inbound','batch',
       'https://samedical.org/estore/',false,true,null,'contact_required',
       'Delivery format/API availability must be agreed with SAMA; do not scrape eMDCM/eCCSA.'
from public.integration_provider where slug='sama'
on conflict (provider_id,name) do nothing;

insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,specification_reference,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'HealthNet ST PMS switch interface','edi_file','bidirectional','both',
       'https://www.medikredit.co.za/products-and-services/healthcare-claims-switching/',
       'MediKredit specified data-file layouts',true,true,null,'contact_required',
       'Public information confirms PMS-vendor accreditation and synchronous/asynchronous switching; exact protocol/auth specs must be obtained.'
from public.integration_provider where slug='medikredit'
on conflict (provider_id,name) do nothing;

insert into public.integration_interface
(provider_id,name,interface_type,direction,sync_mode,documentation_url,accreditation_required,contract_required,sandbox_available,status,notes)
select id,'SwitchOn claims switching interface','other','bidirectional','realtime',
       'https://healthtech.altron.com/product-switchon',false,true,null,'contact_required',
       'Capabilities confirmed publicly; protocol, auth, sandbox and vendor-integration terms must be obtained from Altron.'
from public.integration_provider where slug='altron-switchon'
on conflict (provider_id,name) do nothing;

-- Authoritative/reference datasets.
insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'sa_icd10_mit','South African ICD-10 Master Industry Table','coding','canonical','public_download',false,'release-based',
'https://www.health.gov.za/icd-10-master-industry-table/','active','Code10 canonical SA ICD-10 code-validity dataset.'
from public.integration_provider where slug='ndoh'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'sa_icd10_addendum','PHISC Addendum to SA ICD-10 Coding Standards','coding','reference','public_download',false,'versioned',
'https://www.phisc.net/standards/phisc-standards','active','Current public standards page lists Version 8 (October 2025).'
from public.integration_provider where slug='phisc'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'phisc_ccsa_rules','PHISC CCSA Coding Standards and Guidelines','coding','reference','public_download',false,'versioned',
'https://www.phisc.net/standards/phisc-standards','active','Current public standards page lists Version 12 (October 2025).'
from public.integration_provider where slug='phisc'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'cms_schemes_2026','CMS Registered Medical Schemes 2026','payer','regulatory','public_download',false,'annual',
'https://www.medicalschemes.co.za/latest-publication/circular-12-of-2026-notification-of-registration-of-medical-schemes/','active',
'Authoritative registry baseline; not member-level transactional data.'
from public.integration_provider where slug='cms'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'cms_benefit_options_2026','CMS Approved Benefit Options 2026','payer','regulatory','public_download',false,'annual',
'https://www.medicalschemes.co.za/latest-publication/circular-41-of-2025-open-and-restricted-medical-schemes-approved-benefit-options-and-contribution-adjustments/','active',
'Annual option-status source; does not provide live member benefit balances.'
from public.integration_provider where slug='cms'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'cms_pmb_icd10_2026','CMS 2026 PMB ICD-10 Coded List','coding','regulatory','public_download',false,'release-based',
'https://www.medicalschemes.co.za/wpfd_file/2026-pmb-icd-10-coded-list-distribution-4/','active',
'Guidance layer only; coded-list inclusion does not itself establish PMB entitlement.'
from public.integration_provider where slug='cms'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'sama_ccsa_2026','SAMA eCCSA 2026','coding','licensed','portal',true,'annual',
'https://samedical.org/estore/','contact_required',
'Annual licensing required; data-delivery/integration rights must be negotiated before ingestion.'
from public.integration_provider where slug='sama'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'sama_emdcm_2026','SAMA eMDCM 2026','billing','licensed','portal',true,'annual',
'https://samedical.org/estore/','contact_required',
'Procedure coding/fee-reference content; integration/data-distribution rights not assumed.'
from public.integration_provider where slug='sama'
on conflict (provider_id,dataset_key) do nothing;

insert into public.source_dataset
(provider_id,dataset_key,name,domain,authority_level,access_model,licence_required,update_frequency,evidence_url,status,notes)
select id,'nappi_product_price','NAPPI Product and Price File','coding','licensed','licensed_file',true,'frequent',
'https://www.medikredit.co.za/products-and-services/nappi/nappi-price-files/','contact_required',
'MediKredit states it owns, allocates and maintains NAPPI product/price data.'
from public.integration_provider where slug='medikredit'
on conflict (provider_id,dataset_key) do nothing;

-- Capability evidence.
with p as (select id from public.integration_provider where slug='ndoh')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,'icd10_reference','confirmed_public','https://www.health.gov.za/icd-10-master-industry-table/',
'NDoH publishes the South African ICD-10 Master Industry Table.',now() from p
on conflict do nothing;

with p as (select id from public.integration_provider where slug='phisc')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,'icd10_rules','confirmed_public','https://www.phisc.net/standards/phisc-standards',
'PHISC publishes SA ICD-10 addenda and CCSA coding standards/guidelines.',now() from p
on conflict do nothing;

with p as (select id from public.integration_provider where slug='cms')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,x.code,'confirmed_public',x.url,x.note,now()
from p cross join (values
 ('scheme_registry','https://www.medicalschemes.co.za/latest-publication/circular-12-of-2026-notification-of-registration-of-medical-schemes/','CMS publishes registered medical schemes for 2026.'),
 ('benefit_options_directory','https://www.medicalschemes.co.za/latest-publication/circular-41-of-2025-open-and-restricted-medical-schemes-approved-benefit-options-and-contribution-adjustments/','CMS publishes approved benefit options for 2026.'),
 ('pmb_guidance','https://www.medicalschemes.co.za/resources/pmb/pmb-conditions/','CMS publishes PMB guidance and expressly notes coded lists are guidance rather than automatic entitlement.')
) as x(code,url,note)
on conflict do nothing;

with p as (select id from public.integration_provider where slug='sama')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,'procedure_codes','contract_required','https://samedical.org/estore/',
'SAMA offers 2026 eCCSA/eMDCM under licensing; PracticeCtrl requires integration/data-use rights.',now() from p
on conflict do nothing;

with p as (select id from public.integration_provider where slug='medikredit'),
     i as (select id,provider_id from public.integration_interface where name='HealthNet ST PMS switch interface')
insert into public.integration_capability(provider_id,interface_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select p.id,i.id,x.code,x.level::public.integration_support_level,x.url,x.note,now()
from p join i on i.provider_id=p.id
cross join (values
 ('claim_submit','confirmed_public','https://www.medikredit.co.za/products-and-services/healthcare-claims-switching/','HealthNet ST supports real-time claims switching and PMS-vendor integration.'),
 ('claim_response','confirmed_public','https://www.medikredit.co.za/clients/healthcare-providers/','Claim responses are returned into the provider PMS with tracking.'),
 ('claim_amend','confirmed_public','https://www.medikredit.co.za/clients/healthcare-providers/','Public provider material states claims can be amended and resubmitted.'),
 ('claim_reverse','confirmed_public','https://www.medikredit.co.za/clients/healthcare-providers/','Public provider material states claims can be reversed.'),
 ('era_receive','confirmed_public','https://www.medikredit.co.za/clients/healthcare-providers/','MediKredit supplies ERA to reconcile payments in PMS.'),
 ('member_validation','contract_required','https://www.medikredit.co.za/clients/public-hospitals/','Validation capability is public, but exact PMS-vendor availability/specification must be confirmed.'),
 ('family_validation','contract_required','https://www.medikredit.co.za/clients/public-hospitals/','FamCheck capability is public, but PracticeCtrl access must be contracted/specified.'),
 ('payer_rule_validation','confirmed_public','https://www.medikredit.co.za/clients/private-hospitals/','Public material describes funder-specific adjudication/rule validation.')
) as x(code,level,url,note)
on conflict do nothing;

with p as (select id from public.integration_provider where slug='medikredit')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,'nappi_product_file','contract_required','https://www.medikredit.co.za/products-and-services/nappi/nappi-price-files/',
'MediKredit supplies and maintains NAPPI product/price files; commercial data arrangement required.',now() from p
on conflict do nothing;

with p as (select id from public.integration_provider where slug='altron-switchon'),
     i as (select id,provider_id from public.integration_interface where name='SwitchOn claims switching interface')
insert into public.integration_capability(provider_id,interface_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select p.id,i.id,x.code,'specification_required',x.url,x.note,now()
from p join i on i.provider_id=p.id
cross join (values
 ('member_validation','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms member status validation.'),
 ('benefit_check','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms benefit checking.'),
 ('claim_submit','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms real-time claiming.'),
 ('claim_response','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms medical scheme responses.'),
 ('claim_reverse','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms claim reversals.'),
 ('era_receive','https://healthtech.altron.com/product-switchon','SwitchOn publicly confirms electronic remittance advices.')
) as x(code,url,note)
on conflict do nothing;

with p as (select id from public.integration_provider where slug='healthbridge')
insert into public.integration_capability(provider_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select id,x.code,'research_required',x.url,x.note,now()
from p cross join (values
 ('claim_submit','https://healthbridge.co.za/','Healthbridge publicly provides claims/billing capabilities, but third-party PracticeCtrl integration terms are not established.'),
 ('era_receive','https://help.healthbridgenova.co.za/en/article/how-to-manage-electronic-remittances-in-healthbridge-nova','Healthbridge Nova receives electronic remittances.'),
 ('era_reconcile','https://help.healthbridgenova.co.za/en/article/how-to-manage-electronic-remittances-in-healthbridge-nova','Healthbridge Nova automatically matches many eRAs and exposes unmatched reconciliation.')
) as x(code,url,note)
on conflict do nothing;

-- Commercial/technical work queue.
with p as (select id from public.integration_provider where slug='medikredit'),
     i as (select id,provider_id from public.integration_interface where name='HealthNet ST PMS switch interface')
insert into public.integration_requirement(provider_id,interface_id,requirement_type,title,description,priority,status)
select p.id,i.id,x.rt,x.title,x.description,x.priority,'open'
from p join i on i.provider_id=p.id
cross join (values
 ('commercial_contact','Open PMS-vendor integration discussion','Confirm PracticeCtrl as a prospective PMS/software vendor and request integration onboarding path.','critical'),
 ('technical_specification','Obtain HealthNet ST interface specification','Request current claim, response, amendment, reversal, validation and ERA layouts/protocol documentation.','critical'),
 ('accreditation','Define MediKredit accreditation plan','Obtain accreditation test cases, certification gates, environments and expected timeline.','critical'),
 ('sandbox_credentials','Obtain MediKredit test environment','Request sandbox/UAT credentials and test funder routes once commercial prerequisites are met.','high'),
 ('pricing','Obtain switching/integration commercial model','Request vendor/accreditation/setup and per-transaction pricing applicable to PracticeCtrl.','high'),
 ('data_processing_agreement','Complete privacy/security contracting','Document POPIA roles, processing, sub-processors, retention, incident obligations and data flows.','high'),
 ('data_licence','Obtain NAPPI data rights','Agree NAPPI product/price file licence, update mechanism and permitted PracticeCtrl use.','high')
) as x(rt,title,description,priority)
on conflict do nothing;

with p as (select id from public.integration_provider where slug='altron-switchon'),
     i as (select id,provider_id from public.integration_interface where name='SwitchOn claims switching interface')
insert into public.integration_requirement(provider_id,interface_id,requirement_type,title,description,priority,status)
select p.id,i.id,x.rt,x.title,x.description,x.priority,'open'
from p join i on i.provider_id=p.id
cross join (values
 ('commercial_contact','Open SwitchOn integration discussion','Confirm whether Altron supports independent third-party PMS/PracticeCtrl integration and vendor onboarding.','high'),
 ('technical_specification','Obtain SwitchOn technical interface specification','Request current protocol/API/EDI details for claims, member validation, benefit checks, responses, reversals and eRA.','critical'),
 ('sandbox_credentials','Obtain SwitchOn test environment','Request UAT/sandbox capability after integration path is confirmed.','high'),
 ('pricing','Obtain SwitchOn commercial model','Request setup, transaction and vendor integration pricing.','high'),
 ('data_processing_agreement','Complete privacy/security contracting','Define POPIA processing, retention, security and incident responsibilities.','high')
) as x(rt,title,description,priority)
on conflict do nothing;

with p as (select id from public.integration_provider where slug='sama'),
     i as (select id,provider_id from public.integration_interface where name='SAMA licensed coding content')
insert into public.integration_requirement(provider_id,interface_id,requirement_type,title,description,priority,status)
select p.id,i.id,x.rt,x.title,x.description,x.priority,'open'
from p join i on i.provider_id=p.id
cross join (values
 ('commercial_contact','Open SAMA coding-data discussion','Request licensing route for PracticeCtrl as a software platform rather than a single desktop-user licence.','critical'),
 ('data_licence','Secure CCSA/eMDCM data rights','Obtain explicit rights for server-side search/display/update use in PracticeCtrl.','critical'),
 ('technical_specification','Confirm machine-readable delivery/update mechanism','Ask whether SAMA supplies API, structured data feed or licensed distributable dataset suitable for PMS integration.','high')
) as x(rt,title,description,priority)
on conflict do nothing;

commit;
