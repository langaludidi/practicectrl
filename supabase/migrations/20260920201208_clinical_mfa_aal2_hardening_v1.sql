
begin;

-- Clinical workflow writes require MFA/AAL2. Reads remain available to authorised
-- staff at AAL1 so staff can look up/reference codes without mutating the record.

drop policy if exists coding_session_mfa_insert on public.coding_session;
create policy coding_session_mfa_insert
on public.coding_session
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_session_mfa_update on public.coding_session;
create policy coding_session_mfa_update
on public.coding_session
as restrictive
for update
to authenticated
using ((select auth.jwt()->>'aal') = 'aal2')
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_candidate_mfa_insert on public.coding_candidate_snapshot;
create policy coding_candidate_mfa_insert
on public.coding_candidate_snapshot
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_decision_mfa_insert on public.coding_decision;
create policy coding_decision_mfa_insert
on public.coding_decision
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_confidentiality_mfa_insert on public.coding_confidentiality_event;
create policy coding_confidentiality_mfa_insert
on public.coding_confidentiality_event
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_validation_mfa_insert on public.coding_validation_event;
create policy coding_validation_mfa_insert
on public.coding_validation_event
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_validation_mfa_update on public.coding_validation_event;
create policy coding_validation_mfa_update
on public.coding_validation_event
as restrictive
for update
to authenticated
using ((select auth.jwt()->>'aal') = 'aal2')
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists pmb_review_mfa_insert on public.pmb_review;
create policy pmb_review_mfa_insert
on public.pmb_review
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists pmb_review_mfa_update on public.pmb_review;
create policy pmb_review_mfa_update
on public.pmb_review
as restrictive
for update
to authenticated
using ((select auth.jwt()->>'aal') = 'aal2')
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_ai_mfa_insert on public.coding_ai_interaction;
create policy coding_ai_mfa_insert
on public.coding_ai_interaction
as restrictive
for insert
to authenticated
with check ((select auth.jwt()->>'aal') = 'aal2');

drop policy if exists coding_ai_mfa_update on public.coding_ai_interaction;
create policy coding_ai_mfa_update
on public.coding_ai_interaction
as restrictive
for update
to authenticated
using ((select auth.jwt()->>'aal') = 'aal2')
with check ((select auth.jwt()->>'aal') = 'aal2');

-- Recreate final confirmation with an explicit AAL2 check as defense in depth.
create or replace function public.confirm_coding_decision(
  p_coding_session_id uuid,
  p_code_id uuid,
  p_position text,
  p_sequence_no integer default 1,
  p_decision text default 'ACCEPTED',
  p_decision_reason text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_session public.coding_session%rowtype;
  v_code public.sa_icd10_code%rowtype;
  v_decision_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if coalesce((select auth.jwt()->>'aal'), '') <> 'aal2' then
    raise exception 'MFA assurance level 2 required';
  end if;

  if p_position not in ('primary','secondary') then
    raise exception 'Invalid code position';
  end if;
  if p_sequence_no is null or p_sequence_no < 1 then
    raise exception 'Invalid sequence number';
  end if;
  if p_decision not in ('ACCEPTED','MANUALLY_SELECTED','REPLACED') then
    raise exception 'This RPC only confirms positive coding decisions';
  end if;

  select * into v_session
  from public.coding_session
  where id = p_coding_session_id;

  if not found then
    raise exception 'Coding session not found or not accessible';
  end if;
  if v_session.status <> 'open' then
    raise exception 'Coding session is not open';
  end if;

  select * into v_code
  from public.sa_icd10_code
  where id = p_code_id
    and source_release_id = v_session.mit_release_id;

  if not found then
    raise exception 'ICD-10 code is not part of the session MIT release';
  end if;
  if not v_code.valid_clinical_use then
    raise exception 'ICD-10 code is not valid for clinical use';
  end if;
  if p_position = 'primary' and not v_code.valid_primary then
    raise exception 'ICD-10 code is not valid in the primary position';
  end if;
  if v_code.sa_start_date is not null and v_session.service_date < v_code.sa_start_date then
    raise exception 'ICD-10 code was not yet effective on the service date';
  end if;
  if v_code.sa_end_date is not null and v_session.service_date > v_code.sa_end_date then
    raise exception 'ICD-10 code was no longer effective on the service date';
  end if;

  if exists (
    select 1
    from public.coding_validation_event e
    where e.coding_session_id = p_coding_session_id
      and e.code_id = p_code_id
      and e.severity = 'BLOCKING'
      and e.status in ('open','acknowledged')
  ) then
    raise exception 'Unresolved blocking coding validation exists';
  end if;

  insert into public.coding_decision (
    coding_session_id, practice_id, code_id, decision, position,
    sequence_no, decision_reason, selected_by
  ) values (
    p_coding_session_id, v_session.practice_id, p_code_id, p_decision,
    p_position, p_sequence_no, p_decision_reason, (select auth.uid())
  )
  returning id into v_decision_id;

  insert into public.coding_audit_event (
    practice_id, actor_user_id, actor_role, event_type, entity_type,
    entity_id, source_release_ids, metadata
  ) values (
    v_session.practice_id,
    (select auth.uid()),
    'practitioner',
    'CODE_SELECTED',
    'coding_decision',
    v_decision_id,
    jsonb_strip_nulls(jsonb_build_object(
      'mit_release_id', v_session.mit_release_id,
      'phisc_release_id', v_session.phisc_release_id,
      'cms_release_id', v_session.cms_release_id
    )),
    jsonb_build_object(
      'coding_session_id', p_coding_session_id,
      'code_id', p_code_id,
      'code', v_code.code,
      'position', p_position,
      'sequence_no', p_sequence_no,
      'decision', p_decision,
      'aal', (select auth.jwt()->>'aal')
    )
  );

  return v_decision_id;
end;
$$;

revoke all on function public.confirm_coding_decision(uuid, uuid, text, integer, text, text)
  from public, anon;
grant execute on function public.confirm_coding_decision(uuid, uuid, text, integer, text, text)
  to authenticated;

commit;
