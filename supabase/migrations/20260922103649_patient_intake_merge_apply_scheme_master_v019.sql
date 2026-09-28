
create or replace function public.apply_patient_intake(p_intake_id uuid,p_mode text,p_patient_id uuid default null,p_notes text default null)
returns uuid language plpgsql security invoker set search_path=public,vault,pg_temp as $$
declare
 v_user uuid:=(select auth.uid()); s public.patient_intake_session%rowtype; d jsonb; p jsonb; c jsonb; f jsonb; a jsonb; e jsonb; pref jsonb; v_patient uuid; v_scheme uuid; v_option uuid; v_membership uuid; v_name text; v_consent record; v_docs integer:=0; cur public.crm_patient%rowtype; diffs text[]:=array[]::text[]; missing_decisions int:=0;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 select * into s from public.patient_intake_session where id=p_intake_id for update;
 if not found or s.status not in('submitted','validation_required','under_review','verified') then raise exception 'Submitted intake not available for application'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=s.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required'; end if;
 if p_mode not in('create_new','update_existing') then raise exception 'Invalid application mode'; end if;
 if exists(select 1 from public.patient_intake_document x where x.intake_session_id=p_intake_id and x.verification_status='rejected') then raise exception 'Rejected intake documents must be resolved before application'; end if;
 d:=s.submitted_json;p:=coalesce(d->'patient','{}');c:=coalesce(d->'contact','{}');f:=coalesce(d->'funding','{}');a:=coalesce(d->'address','{}');e:=coalesce(d->'emergency_contact','{}');pref:=coalesce(d->'communication_preferences','{}');
 v_name:=trim(concat_ws(' ',nullif(trim(p->>'first_name'),''),nullif(trim(p->>'last_name'),'')));if length(v_name)<2 or nullif(p->>'date_of_birth','') is null then raise exception 'Patient identity fields are incomplete'; end if;

 if p_mode='update_existing' then
   v_patient:=coalesce(p_patient_id,s.existing_patient_id);
   select * into cur from public.crm_patient x where x.id=v_patient and x.practice_id=s.practice_id for update;
   if not found then raise exception 'Existing patient not found in selected practice'; end if;
   if cur.first_name is distinct from nullif(trim(p->>'first_name'),'') then diffs:=array_append(diffs,'first_name');end if;
   if cur.last_name is distinct from nullif(trim(p->>'last_name'),'') then diffs:=array_append(diffs,'last_name');end if;
   if cur.date_of_birth is distinct from (p->>'date_of_birth')::date then diffs:=array_append(diffs,'date_of_birth');end if;
   if cur.primary_phone is distinct from nullif(trim(c->>'mobile'),'') then diffs:=array_append(diffs,'primary_phone');end if;
   if cur.primary_email is distinct from nullif(trim(c->>'email'),'') then diffs:=array_append(diffs,'primary_email');end if;
   select count(*) into missing_decisions from unnest(diffs) k where not exists(select 1 from public.patient_intake_merge_decision md where md.intake_session_id=s.id and md.patient_id=v_patient and md.field_key=k);
   if missing_decisions>0 then raise exception 'Field-level reconciliation is required before updating an existing patient';end if;
   update public.crm_patient set
    first_name=case when coalesce((select decision from public.patient_intake_merge_decision where intake_session_id=s.id and field_key='first_name'),'keep_current')='accept_submitted' then nullif(trim(p->>'first_name'),'') else cur.first_name end,
    last_name=case when coalesce((select decision from public.patient_intake_merge_decision where intake_session_id=s.id and field_key='last_name'),'keep_current')='accept_submitted' then nullif(trim(p->>'last_name'),'') else cur.last_name end,
    date_of_birth=case when coalesce((select decision from public.patient_intake_merge_decision where intake_session_id=s.id and field_key='date_of_birth'),'keep_current')='accept_submitted' then (p->>'date_of_birth')::date else cur.date_of_birth end,
    primary_phone=case when coalesce((select decision from public.patient_intake_merge_decision where intake_session_id=s.id and field_key='primary_phone'),'keep_current')='accept_submitted' then nullif(trim(c->>'mobile'),'') else cur.primary_phone end,
    primary_email=case when coalesce((select decision from public.patient_intake_merge_decision where intake_session_id=s.id and field_key='primary_email'),'keep_current')='accept_submitted' then nullif(trim(c->>'email'),'') else cur.primary_email end,
    data_quality_status='reviewed',updated_by=v_user,updated_at=now()
   where id=v_patient;
   select trim(concat_ws(' ',first_name,last_name)) into v_name from public.crm_patient where id=v_patient;
   update public.crm_patient set display_name=v_name where id=v_patient;
 else
   if exists(select 1 from public.patient_intake_match_candidate mc where mc.intake_session_id=p_intake_id and mc.status='confirmed_match') then raise exception 'A confirmed existing-patient match prevents creating a duplicate'; end if;
   v_patient:=gen_random_uuid();
   insert into public.crm_patient(id,practice_id,source_system,source_patient_ref,first_name,last_name,display_name,date_of_birth,primary_phone,primary_email,status,data_quality_status,created_by,updated_by)
   values(v_patient,s.practice_id,'PracticeCtrl Intake',p_intake_id::text,nullif(trim(p->>'first_name'),''),nullif(trim(p->>'last_name'),''),v_name,(p->>'date_of_birth')::date,nullif(trim(c->>'mobile'),''),nullif(trim(c->>'email'),''),'active','reviewed',v_user,v_user);
 end if;

 update public.patient_address set active=false,updated_at=now() where practice_id=s.practice_id and patient_id=v_patient and address_type='physical' and active;
 if a<>'{}'::jsonb and coalesce(trim(a->>'line1'),'')<>'' then insert into public.patient_address(practice_id,patient_id,address_type,line1,line2,suburb,city,province,postal_code,country_code,created_by) values(s.practice_id,v_patient,'physical',nullif(trim(a->>'line1'),''),nullif(trim(a->>'line2'),''),nullif(trim(a->>'suburb'),''),nullif(trim(a->>'city'),''),nullif(trim(a->>'province'),''),nullif(trim(a->>'postal_code'),''),coalesce(nullif(trim(a->>'country_code'),''),'ZA'),v_user);end if;
 if coalesce(trim(e->>'full_name'),'')<>'' and coalesce(trim(e->>'phone'),'')<>'' then update public.patient_emergency_contact set active=false,updated_at=now() where practice_id=s.practice_id and patient_id=v_patient and active;insert into public.patient_emergency_contact(practice_id,patient_id,full_name,relationship,phone,email,created_by) values(s.practice_id,v_patient,trim(e->>'full_name'),nullif(trim(e->>'relationship'),''),trim(e->>'phone'),nullif(trim(e->>'email'),''),v_user);end if;
 insert into public.patient_communication_preference(patient_id,practice_id,preferred_channel,appointment_reminders,account_notifications,clinical_notifications,results_notifications,marketing_messages,updated_by) values(v_patient,s.practice_id,nullif(trim(pref->>'preferred_channel'),''),coalesce((pref->>'appointment_reminders')::boolean,true),coalesce((pref->>'account_notifications')::boolean,true),coalesce((pref->>'clinical_notifications')::boolean,true),coalesce((pref->>'results_notifications')::boolean,true),coalesce((pref->>'marketing_messages')::boolean,false),v_user) on conflict(patient_id) do update set preferred_channel=excluded.preferred_channel,appointment_reminders=excluded.appointment_reminders,account_notifications=excluded.account_notifications,clinical_notifications=excluded.clinical_notifications,results_notifications=excluded.results_notifications,marketing_messages=excluded.marketing_messages,updated_by=v_user,updated_at=now();

 if f->>'type'='medical_scheme' then
   if nullif(f->>'medical_scheme_id','') is not null then select id,name into v_scheme,v_name from public.medical_scheme where id=(f->>'medical_scheme_id')::uuid and regulatory_status='active'; if v_scheme is null then raise exception 'Selected medical scheme is unavailable';end if; f:=jsonb_set(f,'{scheme_name}',to_jsonb(v_name)); else select id into v_scheme from public.medical_scheme where lower(name)=lower(trim(f->>'scheme_name')) and regulatory_status='active' order by last_verified_at desc nulls last limit 1;end if;
   if nullif(f->>'medical_scheme_option_id','') is not null then select id into v_option from public.medical_scheme_option where id=(f->>'medical_scheme_option_id')::uuid and medical_scheme_id=v_scheme and approval_status='approved';if v_option is null then raise exception 'Selected medical scheme option is unavailable or does not belong to the selected scheme';end if;else if v_scheme is not null and coalesce(trim(f->>'option_name'),'')<>'' then select id into v_option from public.medical_scheme_option where medical_scheme_id=v_scheme and lower(option_name)=lower(trim(f->>'option_name')) and approval_status='approved' order by benefit_year desc limit 1;end if;end if;
   v_membership:=public.upsert_patient_scheme_membership(null,s.practice_id,v_patient,trim(f->>'scheme_name'),nullif(trim(f->>'option_name'),''),trim(f->>'member_number'),nullif(trim(f->>'dependant_code'),''),v_scheme,v_option,'PracticeCtrl Intake',p_intake_id::text,v_user);
 end if;
 for v_consent in select * from public.patient_intake_consent_acceptance where intake_session_id=p_intake_id and status='accepted' loop if not exists(select 1 from public.patient_consent pc where pc.practice_id=s.practice_id and pc.patient_id=v_patient and pc.consent_type=v_consent.consent_key and pc.consent_scope='intake:'||v_consent.document_version and pc.status='granted') then insert into public.patient_consent(practice_id,patient_id,consent_type,consent_scope,status,granted_at,effective_from,recorded_by) values(s.practice_id,v_patient,v_consent.consent_key,'intake:'||v_consent.document_version,'granted',coalesce(v_consent.accepted_at,now()),current_date,v_user);end if;end loop;
 v_docs:=public.promote_patient_intake_documents(p_intake_id,v_patient);
 update public.patient_intake_session set status='applied',review_decision=p_mode,review_notes=p_notes,reviewed_by=v_user,reviewed_at=coalesce(reviewed_at,now()),applied_patient_id=v_patient,applied_at=now(),token_hash=null,token_expires_at=null,updated_at=now() where id=p_intake_id;
 if s.appointment_id is not null then update public.practice_appointment set patient_id=v_patient,registration_status='verified',registration_verified_at=now(),updated_by=v_user,updated_at=now() where id=s.appointment_id and practice_id=s.practice_id;end if;
 insert into public.patient_intake_event(intake_session_id,event_type,actor_type,actor_user_id,metadata) values(p_intake_id,'applied','staff',v_user,jsonb_build_object('mode',p_mode,'patient_id',v_patient,'scheme_membership_id',v_membership,'promoted_documents',v_docs,'merge_decisions',(select coalesce(jsonb_object_agg(field_key,decision),'{}'::jsonb) from public.patient_intake_merge_decision where intake_session_id=s.id),'notes',p_notes));
 return v_patient;
end $$;

