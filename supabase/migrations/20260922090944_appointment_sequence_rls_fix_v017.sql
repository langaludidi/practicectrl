
create policy appointment_sequence_staff_read on public.appointment_sequence
for select to authenticated
using (exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=appointment_sequence.practice_id and m.active));

