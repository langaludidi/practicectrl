
create table if not exists public.patient_intake_merge_decision(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references public.patient_intake_session(id) on delete cascade,
 practice_id uuid not null references public.practice(id) on delete cascade,
 patient_id uuid not null references public.crm_patient(id) on delete cascade,
 field_key text not null,
 current_value jsonb,
 submitted_value jsonb,
 decision text not null check(decision in('keep_current','accept_submitted')),
 decided_by uuid not null references auth.users(id) on delete restrict,
 decided_at timestamptz not null default now(),
 unique(intake_session_id,field_key)
);
alter table public.patient_intake_merge_decision enable row level security;
create index if not exists patient_intake_merge_practice_idx on public.patient_intake_merge_decision(practice_id,intake_session_id);
create index if not exists patient_intake_merge_patient_idx on public.patient_intake_merge_decision(patient_id,intake_session_id);
drop policy if exists patient_intake_merge_staff_read on public.patient_intake_merge_decision;
create policy patient_intake_merge_staff_read on public.patient_intake_merge_decision for select to authenticated using(
 exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_merge_decision.practice_id and m.active)
);
revoke all on public.patient_intake_merge_decision from anon;
grant select on public.patient_intake_merge_decision to authenticated;

create or replace function public.validate_sa_id(p_id text,p_confirmed_dob date default null)
returns jsonb language plpgsql immutable set search_path='' as $$
declare s text:=regexp_replace(coalesce(p_id,''),'\s','','g'); total int:=0; i int; d int; dbl int; yy int; mm int; dd int; century int; dob date; valid_date boolean:=true; luhn boolean:=false;
begin
 if s !~ '^[0-9]{13}$' then return jsonb_build_object('valid',false,'format_valid',false,'luhn_valid',false,'date_valid',false); end if;
 for i in 1..12 loop
   d:=substr(s,i,1)::int;
   if mod(i,2)=1 then total:=total+d; else dbl:=d*2;total:=total+(dbl/10)+(dbl%10);end if;
 end loop;
 luhn:=mod(total+substr(s,13,1)::int,10)=0;
 yy:=substr(s,1,2)::int;mm:=substr(s,3,2)::int;dd:=substr(s,5,2)::int;
 century:=case when yy<=extract(year from current_date)::int%100 then 2000 else 1900 end;
 begin dob:=make_date(century+yy,mm,dd); exception when others then valid_date:=false;dob:=null;end;
 return jsonb_build_object('valid',luhn and valid_date,'format_valid',true,'luhn_valid',luhn,'date_valid',valid_date,'derived_date_of_birth',dob,'dob_matches',case when p_confirmed_dob is null or dob is null then null else p_confirmed_dob=dob end);
end $$;
revoke all on function public.validate_sa_id(text,date) from public,anon;
grant execute on function public.validate_sa_id(text,date) to authenticated,anon;

create or replace function public.get_patient_intake_reconciliation(p_intake_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid());s public.patient_intake_session%rowtype;p public.crm_patient%rowtype;d jsonb;out jsonb:='[]'::jsonb;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 select * into s from public.patient_intake_session where id=p_intake_id;
 if not found or s.existing_patient_id is null then raise exception 'Existing-patient intake not found';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=s.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required';end if;
 select * into p from public.crm_patient where id=s.existing_patient_id and practice_id=s.practice_id;
 d:=coalesce(s.submitted_json,'{}'::jsonb);
 out:=jsonb_build_array(
 jsonb_build_object('field_key','first_name','label','First name','current',to_jsonb(p.first_name),'submitted',to_jsonb(d#>>'{patient,first_name}')),
 jsonb_build_object('field_key','last_name','label','Last name','current',to_jsonb(p.last_name),'submitted',to_jsonb(d#>>'{patient,last_name}')),
 jsonb_build_object('field_key','date_of_birth','label','Date of birth','current',to_jsonb(p.date_of_birth),'submitted',to_jsonb(d#>>'{patient,date_of_birth}')),
 jsonb_build_object('field_key','primary_phone','label','Mobile number','current',to_jsonb(p.primary_phone),'submitted',to_jsonb(d#>>'{contact,mobile}')),
 jsonb_build_object('field_key','primary_email','label','Email','current',to_jsonb(p.primary_email),'submitted',to_jsonb(d#>>'{contact,email}'))
 );
 return jsonb_build_object('intake_id',s.id,'patient_id',p.id,'patient_name',p.display_name,'fields',(select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(out) x where x->'current' is distinct from x->'submitted'),'decisions',(select coalesce(jsonb_object_agg(md.field_key,md.decision),'{}'::jsonb) from public.patient_intake_merge_decision md where md.intake_session_id=s.id));
end $$;
revoke all on function public.get_patient_intake_reconciliation(uuid) from public,anon;
grant execute on function public.get_patient_intake_reconciliation(uuid) to authenticated;

create or replace function public.set_patient_intake_merge_decision(p_intake_id uuid,p_field_key text,p_decision text)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid());s public.patient_intake_session%rowtype;p public.crm_patient%rowtype;d jsonb;cur jsonb;sub jsonb;v_id uuid;allowed text[]:=array['first_name','last_name','date_of_birth','primary_phone','primary_email'];
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 if not p_field_key=any(allowed) or p_decision not in('keep_current','accept_submitted') then raise exception 'Invalid merge decision';end if;
 select * into s from public.patient_intake_session where id=p_intake_id for update;
 if not found or s.existing_patient_id is null or s.status not in('submitted','validation_required','under_review','verified') then raise exception 'Reviewable existing-patient intake not found';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=s.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required';end if;
 select * into p from public.crm_patient where id=s.existing_patient_id and practice_id=s.practice_id;
 d:=coalesce(s.submitted_json,'{}'::jsonb);
 cur:=case p_field_key when 'first_name' then to_jsonb(p.first_name) when 'last_name' then to_jsonb(p.last_name) when 'date_of_birth' then to_jsonb(p.date_of_birth) when 'primary_phone' then to_jsonb(p.primary_phone) when 'primary_email' then to_jsonb(p.primary_email) end;
 sub:=case p_field_key when 'first_name' then to_jsonb(d#>>'{patient,first_name}') when 'last_name' then to_jsonb(d#>>'{patient,last_name}') when 'date_of_birth' then to_jsonb(d#>>'{patient,date_of_birth}') when 'primary_phone' then to_jsonb(d#>>'{contact,mobile}') when 'primary_email' then to_jsonb(d#>>'{contact,email}') end;
 insert into public.patient_intake_merge_decision(intake_session_id,practice_id,patient_id,field_key,current_value,submitted_value,decision,decided_by)
 values(s.id,s.practice_id,p.id,p_field_key,cur,sub,p_decision,v_user)
 on conflict(intake_session_id,field_key) do update set current_value=excluded.current_value,submitted_value=excluded.submitted_value,decision=excluded.decision,decided_by=v_user,decided_at=now()
 returning id into v_id;
 update public.patient_intake_session set status='under_review',reviewed_by=v_user,reviewed_at=coalesce(reviewed_at,now()),updated_at=now() where id=s.id;
 insert into public.patient_intake_event(intake_session_id,event_type,actor_type,actor_user_id,metadata) values(s.id,'merge_decision','staff',v_user,jsonb_build_object('field_key',p_field_key,'decision',p_decision));
 return v_id;
end $$;
revoke all on function public.set_patient_intake_merge_decision(uuid,text,text) from public,anon;
grant execute on function public.set_patient_intake_merge_decision(uuid,text,text) to authenticated;

