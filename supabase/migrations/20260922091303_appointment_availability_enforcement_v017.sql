
create or replace function public.enforce_appointment_schedule()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_tz text; v_local_start timestamp; v_local_end timestamp; v_day smallint; v_date date;
begin
 if new.status not in('booked','confirmed','checked_in','in_progress') then return new; end if;
 if exists(select 1 from public.practitioner_schedule_exception e where e.practice_id=new.practice_id and e.practitioner_id=new.practitioner_id and e.exception_type='unavailable' and tstzrange(e.starts_at,e.ends_at,'[)')&&tstzrange(new.starts_at,new.ends_at,'[)')) then
   raise exception 'Practitioner is unavailable during the requested time';
 end if;
 select coalesce(timezone,'Africa/Johannesburg') into v_tz from public.practice where id=new.practice_id;
 v_local_start:=new.starts_at at time zone v_tz; v_local_end:=new.ends_at at time zone v_tz; v_date:=v_local_start::date; v_day:=extract(dow from v_local_start)::smallint;
 if v_local_end::date<>v_date then raise exception 'Appointments may not span local calendar days'; end if;
 if exists(select 1 from public.practitioner_availability_rule r where r.practice_id=new.practice_id and r.practitioner_id=new.practitioner_id and r.active and r.day_of_week=v_day and (r.effective_from is null or r.effective_from<=v_date) and (r.effective_to is null or r.effective_to>=v_date))
 and not exists(select 1 from public.practitioner_availability_rule r where r.practice_id=new.practice_id and r.practitioner_id=new.practitioner_id and r.active and r.day_of_week=v_day and (r.effective_from is null or r.effective_from<=v_date) and (r.effective_to is null or r.effective_to>=v_date) and r.start_time<=v_local_start::time and r.end_time>=v_local_end::time and (r.location_id is null or new.location_id is null or r.location_id=new.location_id))
 and not exists(select 1 from public.practitioner_schedule_exception e where e.practice_id=new.practice_id and e.practitioner_id=new.practitioner_id and e.exception_type='available_override' and tstzrange(e.starts_at,e.ends_at,'[)')@>new.starts_at and tstzrange(e.starts_at,e.ends_at,'[)')@>(new.ends_at-interval '1 microsecond'))
 then raise exception 'Requested time falls outside practitioner availability'; end if;
 return new;
end $$;
create trigger practice_appointment_schedule_guard before insert or update of practice_id,practitioner_id,location_id,starts_at,ends_at,status on public.practice_appointment for each row execute function public.enforce_appointment_schedule();

