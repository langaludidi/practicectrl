
create table public.patient_intake_document(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references public.patient_intake_session(id) on delete cascade,
 practice_id uuid not null references public.practice(id) on delete cascade,
 document_type text not null check(document_type in('identity_document','medical_scheme_card','referral','proof_of_address','other')),
 storage_bucket text not null default 'patient-intake-files',
 storage_path text not null,
 original_filename text not null,
 mime_type text not null,
 file_size_bytes bigint not null check(file_size_bytes>0 and file_size_bytes<=10485760),
 sha256 text,
 verification_status text not null default 'pending' check(verification_status in('pending','verified','rejected','superseded')),
 verification_notes text,
 verified_by uuid references auth.users(id) on delete set null,
 verified_at timestamptz,
 uploaded_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 unique(storage_bucket,storage_path)
);
create index patient_intake_document_session_idx on public.patient_intake_document(intake_session_id,document_type,verification_status);
create index patient_intake_document_practice_idx on public.patient_intake_document(practice_id,verification_status,uploaded_at desc);
create trigger intake_document_tenant_guard before insert or update of practice_id,intake_session_id on public.patient_intake_document for each row execute function public.enforce_same_practice_reference('patient_intake_session','intake_session_id');

alter table public.patient_intake_document enable row level security;
create policy intake_document_staff_read on public.patient_intake_document for select to authenticated
using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_document.practice_id and m.active));
create policy intake_document_staff_update on public.patient_intake_document for update to authenticated
using(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_document.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')))
with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_document.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
grant select,update on public.patient_intake_document to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('patient-intake-files','patient-intake-files',false,10485760,array['application/pdf','image/jpeg','image/png','image/heic','image/heif'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy patient_intake_files_staff_select on storage.objects for select to authenticated
using(bucket_id='patient-intake-files' and ((select auth.jwt())->>'aal')='aal2' and exists(
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.active and m.practice_id::text=split_part(name,'/',1)
));
create policy patient_intake_files_deny_client_insert on storage.objects for insert to authenticated with check(false);
create policy patient_intake_files_deny_client_update on storage.objects for update to authenticated using(false) with check(false);
create policy patient_intake_files_deny_client_delete on storage.objects for delete to authenticated using(false);

create or replace function public.review_patient_intake_document(p_document_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); v_practice uuid; v_session uuid;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 if p_status not in('verified','rejected') then raise exception 'Invalid document verification status'; end if;
 select practice_id,intake_session_id into v_practice,v_session from public.patient_intake_document where id=p_document_id for update;
 if not found then raise exception 'Intake document not found'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_practice and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required'; end if;
 update public.patient_intake_document set verification_status=p_status,verification_notes=p_notes,verified_by=v_user,verified_at=now() where id=p_document_id;
 insert into public.patient_intake_event(intake_session_id,event_type,actor_type,actor_user_id,metadata)
 values(v_session,'document_reviewed','staff',v_user,jsonb_build_object('document_id',p_document_id,'status',p_status,'notes',p_notes));
end $$;
revoke all on function public.review_patient_intake_document(uuid,text,text) from public,anon;
grant execute on function public.review_patient_intake_document(uuid,text,text) to authenticated;

