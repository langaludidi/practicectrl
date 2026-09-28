
create or replace function public.resolve_patient_intake_token(p_token text)
returns table(id uuid,practice_id uuid,practice_name text,appointment_at timestamptz,status text,form_version integer,draft_json jsonb,opened_at timestamptz)
language sql security definer set search_path=public,extensions,pg_temp as $$
 select s.id,s.practice_id,p.name,a.starts_at,s.status,s.form_version,s.draft_json,s.opened_at
 from public.patient_intake_session s
 join public.practice p on p.id=s.practice_id
 left join public.practice_appointment a on a.id=s.appointment_id
 where s.token_hash=encode(digest(p_token,'sha256'),'hex')
   and s.token_expires_at>now()
   and s.status not in('expired','cancelled','applied')
 limit 1
$$;
revoke all on function public.resolve_patient_intake_token(text) from public,anon,authenticated;
grant execute on function public.resolve_patient_intake_token(text) to service_role;

