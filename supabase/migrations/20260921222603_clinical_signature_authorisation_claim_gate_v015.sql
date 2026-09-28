create or replace function public.guard_clinical_note_integrity()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
begin
  if old.practice_id is distinct from new.practice_id
    or old.patient_id is distinct from new.patient_id
    or old.encounter_id is distinct from new.encounter_id
    or old.author_user_id is distinct from new.author_user_id
    or old.amendment_of_note_id is distinct from new.amendment_of_note_id then
    raise exception 'Clinical note identity/provenance is immutable';
  end if;

  if old.status in ('signed','amended') and (
    old.note_type is distinct from new.note_type
    or old.title is distinct from new.title
    or old.subjective is distinct from new.subjective
    or old.objective is distinct from new.objective
    or old.assessment is distinct from new.assessment
    or old.plan is distinct from new.plan
    or old.narrative is distinct from new.narrative
    or old.structured_data is distinct from new.structured_data
    or old.content_sha256 is distinct from new.content_sha256
    or old.signed_by is distinct from new.signed_by
    or old.signed_at is distinct from new.signed_at
  ) then
    raise exception 'Signed clinical note content is immutable; create an amendment';
  end if;

  if old.status='draft' and new.status='signed'
     and coalesce(current_setting('practicectrl.clinical_signing',true),'')<>'on' then
    raise exception 'Clinical notes must be signed through the governed signing action';
  end if;

  if old.status in ('signed','amended') and new.status is distinct from old.status
     and coalesce(current_setting('practicectrl.clinical_signing',true),'')<>'on' then
    raise exception 'Signed clinical note lifecycle changes require a governed clinical action';
  end if;

  return new;
end;
$$;
drop trigger if exists trg_guard_clinical_note_integrity on public.clinical_note;
create trigger trg_guard_clinical_note_integrity
before update on public.clinical_note
for each row execute function public.guard_clinical_note_integrity();

create or replace function public.sign_clinical_note(p_note_id uuid) returns uuid
language plpgsql
security invoker
set search_path=public,extensions,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_note public.clinical_note%rowtype;
  v_hash text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_note from public.clinical_note where id=p_note_id for update;
  if not found then raise exception 'Clinical note not found or not accessible'; end if;
  if v_note.status<>'draft' then raise exception 'Only a draft clinical note can be signed'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_note.practice_id and m.active and m.role='practitioner') then raise exception 'Practitioner role required to sign a clinical note'; end if;
  if v_note.author_user_id<>v_user and not exists(select 1 from public.practice_encounter e where e.id=v_note.encounter_id and e.practitioner_user_id=v_user) then raise exception 'Only the author or encounter practitioner may sign this note'; end if;
  if length(trim(coalesce(v_note.assessment,v_note.narrative,'')))<2 then raise exception 'Clinical assessment or narrative is required before signing'; end if;

  v_hash:=encode(extensions.digest(concat_ws('|',v_note.practice_id::text,v_note.patient_id::text,v_note.encounter_id::text,v_note.note_type,coalesce(v_note.title,''),coalesce(v_note.subjective,''),coalesce(v_note.objective,''),coalesce(v_note.assessment,''),coalesce(v_note.plan,''),coalesce(v_note.narrative,''),v_note.structured_data::text),'sha256'),'hex');
  perform set_config('practicectrl.clinical_signing','on',true);

  update public.clinical_note set status='signed',signed_by=v_user,signed_at=now(),content_sha256=v_hash,updated_at=now() where id=p_note_id;

  if v_note.amendment_of_note_id is not null then
    update public.clinical_note
    set status='amended',updated_at=now()
    where id=v_note.amendment_of_note_id and status='signed';
    insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata)
    values(v_note.amendment_of_note_id,'amended',v_user,jsonb_build_object('replacement_note_id',p_note_id));
  end if;

  insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(p_note_id,'signed',v_user,jsonb_build_object('content_sha256',v_hash));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_note.practice_id,v_note.patient_id,'clinical',now(),'Clinical note signed',coalesce(v_note.title,initcap(replace(v_note.note_type,'_',' '))),'clinical_note',p_note_id,v_user,'PracticeCtrl',jsonb_build_object('content_sha256',v_hash,'amendment_of_note_id',v_note.amendment_of_note_id));
  return p_note_id;
end;
$$;

create or replace function public.assess_claim_submission_readiness(p_claim_id uuid)
returns jsonb
language plpgsql
stable
set search_path=public,pg_temp
as $$
declare
  v_claim public.claim_record%rowtype;
  v_invoice public.billing_invoice%rowtype;
  v_reasons jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_mit boolean := false;
  v_ccsa boolean := false;
  v_membership boolean := false;
  v_route boolean := false;
  v_authorisation boolean := true;
  v_line_count integer := 0;
begin
  select * into v_claim from public.claim_record where id=p_claim_id;
  if not found then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Claim not found or not accessible'),'warnings','[]'::jsonb);
  end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=v_claim.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin','auditor')
  ) then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Finance-authorised PracticeCtrl role required'),'warnings','[]'::jsonb);
  end if;

  if v_claim.invoice_id is null then
    v_reasons:=v_reasons||jsonb_build_array('Claim is not linked to an invoice');
  else
    select * into v_invoice from public.billing_invoice where id=v_claim.invoice_id;
    if not found then
      v_reasons:=v_reasons||jsonb_build_array('Linked invoice is unavailable');
    elsif v_invoice.status not in ('final','part_paid','outstanding','paid') then
      v_reasons:=v_reasons||jsonb_build_array('Linked invoice is not finalised');
    end if;
  end if;

  if v_claim.patient_id is null then v_reasons:=v_reasons||jsonb_build_array('Claim has no patient link'); end if;
  if v_claim.medical_scheme_id is null then v_reasons:=v_reasons||jsonb_build_array('Claim has no medical scheme link'); end if;

  select count(*) into v_line_count from public.claim_line where claim_id=p_claim_id;
  if v_line_count<1 then v_reasons:=v_reasons||jsonb_build_array('Claim has no claim lines'); end if;
  if exists (select 1 from public.claim_line l where l.claim_id=p_claim_id and (cardinality(l.diagnosis_codes)=0 or l.code_system<>'SAMA_CCSA')) then
    v_reasons:=v_reasons||jsonb_build_array('One or more claim lines lack diagnosis coding or licensed SAMA CCSA procedure coding');
  end if;

  select exists(select 1 from public.coding_source_release where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active') into v_mit;
  if not v_mit then v_reasons:=v_reasons||jsonb_build_array('No active authoritative NDoH MIT release is available'); end if;

  select exists(
    select 1 from public.billing_code_reference r
    join public.source_dataset_release sr on sr.id=r.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA' and r.active and sr.status='active' and d.licence_required=true
  ) into v_ccsa;
  if not v_ccsa then v_reasons:=v_reasons||jsonb_build_array('No active licensed SAMA CCSA dataset is available'); end if;

  if v_claim.patient_id is not null and v_claim.medical_scheme_id is not null then
    select exists(
      select 1 from public.crm_patient_scheme_membership m
      where m.practice_id=v_claim.practice_id
        and m.patient_id=v_claim.patient_id
        and m.medical_scheme_id=v_claim.medical_scheme_id
        and (v_claim.medical_scheme_option_id is null or m.medical_scheme_option_id=v_claim.medical_scheme_option_id)
        and m.membership_status='active_verified'
        and (m.effective_from is null or m.effective_from<=coalesce(v_claim.service_from,current_date))
        and (m.effective_to is null or m.effective_to>=coalesce(v_claim.service_to,v_claim.service_from,current_date))
    ) into v_membership;
  end if;
  if not v_membership then v_reasons:=v_reasons||jsonb_build_array('No active verified scheme membership matches this patient/scheme/option/service date'); end if;

  if v_claim.scheme_authorisation_id is not null then
    select exists(
      select 1 from public.scheme_authorisation a
      where a.id=v_claim.scheme_authorisation_id
        and a.practice_id=v_claim.practice_id
        and a.patient_id=v_claim.patient_id
        and a.status in ('approved','partially_approved')
        and nullif(trim(a.authorisation_number),'') is not null
        and (a.medical_scheme_id is null or a.medical_scheme_id=v_claim.medical_scheme_id)
        and (a.medical_scheme_option_id is null or v_claim.medical_scheme_option_id is null or a.medical_scheme_option_id=v_claim.medical_scheme_option_id)
        and (a.effective_from is null or a.effective_from<=coalesce(v_claim.service_from,current_date))
        and (a.effective_to is null or a.effective_to>=coalesce(v_claim.service_to,v_claim.service_from,current_date))
    ) into v_authorisation;
    if not v_authorisation then
      v_reasons:=v_reasons||jsonb_build_array('Linked medical-scheme authorisation is not approved or is not valid for this claim/service date');
    end if;
  end if;

  if v_claim.medical_scheme_id is not null then
    select exists(
      select 1
      from public.payer_transaction_route r
      join public.integration_adapter_capability a on a.provider_id=r.provider_id and a.interface_id=r.interface_id and a.capability_code='claim_submit'
      join public.practice_integration_connection c on c.practice_id=v_claim.practice_id and c.provider_id=r.provider_id and c.interface_id=r.interface_id and c.environment='production' and c.status in ('production_ready','active')
      where r.medical_scheme_id=v_claim.medical_scheme_id
        and (r.medical_scheme_option_id is null or r.medical_scheme_option_id=v_claim.medical_scheme_option_id)
        and r.capability_code='claim_submit'
        and r.support_status<>'not_supported'
        and a.executable_production=true
        and a.implementation_status in ('accredited','production_ready')
        and nullif(btrim(a.accreditation_reference),'') is not null
        and a.accreditation_verified_at is not null
        and (a.accreditation_expires_at is null or a.accreditation_expires_at >= current_timestamp)
        and (r.effective_from is null or r.effective_from<=coalesce(v_claim.service_from,current_date))
        and (r.effective_to is null or r.effective_to>=coalesce(v_claim.service_to,v_claim.service_from,current_date))
    ) into v_route;
  end if;
  if not v_route then v_reasons:=v_reasons||jsonb_build_array('No accredited executable production claim route exists for this scheme/option'); end if;

  if v_claim.claim_status<>'draft' then v_warnings:=v_warnings||jsonb_build_array('Claim is not in draft status; submission controls must respect the existing lifecycle state'); end if;
  if v_claim.total_claimed<=0 then v_reasons:=v_reasons||jsonb_build_array('Claimed amount must be greater than zero'); end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_reasons)=0 and v_claim.claim_status='draft',
    'reasons',v_reasons,'warnings',v_warnings,'claim_id',p_claim_id,'claim_status',v_claim.claim_status,'claim_lines',v_line_count,
    'authoritative_mit_active',v_mit,'licensed_procedure_data_active',v_ccsa,'verified_membership_active',v_membership,
    'linked_authorisation_valid',v_authorisation,'production_route_active',v_route
  );
end;
$$;
