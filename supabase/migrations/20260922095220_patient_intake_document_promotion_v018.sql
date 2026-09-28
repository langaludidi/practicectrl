
alter table public.patient_intake_document add column if not exists promoted_document_id uuid references public.patient_document(id) on delete set null;
create index if not exists patient_intake_document_promoted_idx on public.patient_intake_document(promoted_document_id) where promoted_document_id is not null;
create index if not exists patient_intake_document_verified_by_idx on public.patient_intake_document(verified_by) where verified_by is not null;

create or replace function public.promote_patient_intake_documents(p_intake_id uuid,p_patient_id uuid)
returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); s public.patient_intake_session%rowtype; d record; v_doc uuid; n integer:=0;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 select * into s from public.patient_intake_session where id=p_intake_id for update;
 if not found then raise exception 'Patient intake not found'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=s.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required'; end if;
 if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=s.practice_id) then raise exception 'Patient not found in selected practice'; end if;
 for d in select * from public.patient_intake_document where intake_session_id=p_intake_id and verification_status='verified' and promoted_document_id is null order by uploaded_at loop
   v_doc:=gen_random_uuid();
   insert into public.patient_document(id,practice_id,patient_id,document_type,title,clinical_data,status,content_json,storage_bucket,storage_path,mime_type,byte_size,sha256,created_by,generated_at)
   values(v_doc,s.practice_id,p_patient_id,d.document_type,d.original_filename,false,'final',jsonb_build_object('source','patient_intake','intake_session_id',p_intake_id,'intake_document_id',d.id,'verified_at',d.verified_at),d.storage_bucket,d.storage_path,d.mime_type,d.file_size_bytes,d.sha256,v_user,now());
   update public.patient_intake_document set promoted_document_id=v_doc where id=d.id;
   insert into public.patient_document_event(document_id,event_type,actor_user_id,metadata) values(v_doc,'created',v_user,jsonb_build_object('source','patient_intake','intake_session_id',p_intake_id));
   n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.promote_patient_intake_documents(uuid,uuid) from public,anon;
grant execute on function public.promote_patient_intake_documents(uuid,uuid) to authenticated;

create or replace function public.get_patient_intake_document_access(p_document_id uuid,p_expires_seconds integer default 300)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); d public.patient_intake_document%rowtype;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 if p_expires_seconds<60 or p_expires_seconds>900 then raise exception 'Expiry must be between 60 and 900 seconds'; end if;
 select * into d from public.patient_intake_document where id=p_document_id;
 if not found then raise exception 'Document not found'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=d.practice_id and m.active) then raise exception 'Document access denied'; end if;
 return jsonb_build_object('bucket',d.storage_bucket,'path',d.storage_path,'expires_seconds',p_expires_seconds,'filename',d.original_filename,'mime_type',d.mime_type);
end $$;
revoke all on function public.get_patient_intake_document_access(uuid,integer) from public,anon;
grant execute on function public.get_patient_intake_document_access(uuid,integer) to authenticated;

