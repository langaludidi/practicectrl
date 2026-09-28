
begin;

revoke insert,update,delete on table public.source_file from authenticated;
drop policy if exists source_file_system_admin_insert on public.source_file;
drop policy if exists source_file_system_admin_update on public.source_file;

drop policy if exists governed_source_files_admin_insert on storage.objects;
-- No authenticated INSERT/UPDATE/DELETE policy remains for governed-source-files.
-- Trusted server routes write with the Supabase secret key after AAL2/system_admin verification.

commit;
