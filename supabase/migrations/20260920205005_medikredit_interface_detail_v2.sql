
begin;

update public.integration_interface i
set name='HealthNet ST XML/web-services interface',
    interface_type='api',
    direction='bidirectional',
    sync_mode='both',
    specification_reference='MediKredit XML specification and XSD request/response validation',
    sandbox_available=true,
    status='contact_required',
    notes='Public PMS-vendor documentation states HealthNet ST integration supports real-time end-to-end claims adjudication via an XML specification. The same specification accommodates eligibilities, FamCheck, AuthCheck, claims, reversals, resubmissions and re-sends. Claims may be submitted via web services or HealthNet ST. MediKredit provides PMS vendors a dedicated test environment with current funder rules, NAPPI, tariff/pricing configurations and dummy beneficiaries, followed by accreditation.'
from public.integration_provider p
where i.provider_id=p.id
  and p.slug='medikredit'
  and i.name='HealthNet ST PMS switch interface';

update public.integration_capability c
set support_level='confirmed_public',
    evidence_url='https://www.medikredit.co.za/clients/practice-management-software-vendors/',
    evidence_note=case c.capability_code
      when 'member_validation' then 'MediKredit PMS-vendor documentation states its XML specification accommodates eligibilities.'
      when 'family_validation' then 'MediKredit PMS-vendor documentation states its XML specification accommodates FamCheck.'
      else c.evidence_note
    end,
    last_verified_at=now()
from public.integration_provider p
where c.provider_id=p.id
  and p.slug='medikredit'
  and c.capability_code in ('member_validation','family_validation');

insert into public.integration_capability_catalog
(code,display_name,domain,description,requires_patient_context,transactional)
values
('authorisation_rule_check','Authorisation rule check','claims',
 'Retrieve/check patient or funder authorisation rules where supported; distinct from creating a pre-authorisation request.',true,true)
on conflict (code) do nothing;

insert into public.integration_capability
(provider_id,interface_id,capability_code,support_level,evidence_url,evidence_note,last_verified_at)
select p.id,i.id,'authorisation_rule_check','confirmed_public',
       'https://www.medikredit.co.za/clients/practice-management-software-vendors/',
       'MediKredit PMS-vendor documentation states the XML specification accommodates AuthCheck. This is recorded as an authorisation rule-check capability and is not assumed to be pre-authorisation submission.',
       now()
from public.integration_provider p
join public.integration_interface i on i.provider_id=p.id
where p.slug='medikredit'
  and i.name='HealthNet ST XML/web-services interface'
on conflict do nothing;

commit;
