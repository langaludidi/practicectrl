begin;

-- Core clinical notes and observations are practitioner-only.
drop policy if exists clinical_note_read on public.clinical_note;
create policy clinical_note_read on public.clinical_note for select to authenticated using (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_note.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_insert on public.clinical_note;
create policy clinical_note_insert on public.clinical_note for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and author_user_id=(select auth.uid())
  and status='draft'
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_note.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_update on public.clinical_note;
create policy clinical_note_update on public.clinical_note for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and status='draft'
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_note.practice_id
      and m.active
      and m.role='practitioner'
  )
  and (
    author_user_id=(select auth.uid())
    or exists(
      select 1 from public.practice_encounter e
      where e.id=clinical_note.encounter_id
        and e.practitioner_user_id=(select auth.uid())
    )
  )
) with check (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_note.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_diagnosis_read on public.clinical_note_diagnosis;
create policy clinical_note_diagnosis_read on public.clinical_note_diagnosis for select to authenticated using (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_note_diagnosis.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_diagnosis_insert on public.clinical_note_diagnosis;
create policy clinical_note_diagnosis_insert on public.clinical_note_diagnosis for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(
    select 1
    from public.clinical_note n
    join public.practice_staff_member m on m.practice_id=n.practice_id
    where n.id=clinical_note_diagnosis.note_id
      and n.practice_id=clinical_note_diagnosis.practice_id
      and n.status='draft'
      and m.user_id=(select auth.uid())
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_diagnosis_delete on public.clinical_note_diagnosis;
create policy clinical_note_diagnosis_delete on public.clinical_note_diagnosis for delete to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1
    from public.clinical_note n
    join public.practice_staff_member m on m.practice_id=n.practice_id
    where n.id=clinical_note_diagnosis.note_id
      and n.status='draft'
      and m.user_id=(select auth.uid())
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_observation_read on public.clinical_observation;
create policy clinical_observation_read on public.clinical_observation for select to authenticated using (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_observation.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_observation_insert on public.clinical_observation;
create policy clinical_observation_insert on public.clinical_observation for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and recorded_by=(select auth.uid())
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=clinical_observation.practice_id
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_event_read on public.clinical_note_event;
create policy clinical_note_event_read on public.clinical_note_event for select to authenticated using (
  exists(
    select 1
    from public.clinical_note n
    join public.practice_staff_member m on m.practice_id=n.practice_id
    where n.id=clinical_note_event.note_id
      and m.user_id=(select auth.uid())
      and m.active
      and m.role='practitioner'
  )
);

drop policy if exists clinical_note_event_insert on public.clinical_note_event;
create policy clinical_note_event_insert on public.clinical_note_event for insert to authenticated with check (
  actor_user_id=(select auth.uid())
  and exists(
    select 1
    from public.clinical_note n
    join public.practice_staff_member m on m.practice_id=n.practice_id
    where n.id=clinical_note_event.note_id
      and m.user_id=(select auth.uid())
      and m.active
      and m.role='practitioner'
  )
);

-- Clinical patient documents are practitioner-only; administrative documents remain available
-- to active same-practice staff according to the existing document workflow.
drop policy if exists patient_document_read on public.patient_document;
create policy patient_document_read on public.patient_document for select to authenticated using (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_document.practice_id
      and m.active
      and (
        not patient_document.clinical_data
        or m.role='practitioner'
      )
  )
);

drop policy if exists patient_document_insert on public.patient_document;
create policy patient_document_insert on public.patient_document for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_document.practice_id
      and m.active
      and m.role<>'auditor'
      and (
        not patient_document.clinical_data
        or m.role='practitioner'
      )
  )
);

drop policy if exists patient_document_update on public.patient_document;
create policy patient_document_update on public.patient_document for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and status in ('draft','generated')
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_document.practice_id
      and m.active
      and m.role<>'auditor'
      and (
        not patient_document.clinical_data
        or m.role='practitioner'
      )
  )
) with check (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_document.practice_id
      and m.active
      and m.role<>'auditor'
      and (
        not patient_document.clinical_data
        or m.role='practitioner'
      )
  )
);

commit;
