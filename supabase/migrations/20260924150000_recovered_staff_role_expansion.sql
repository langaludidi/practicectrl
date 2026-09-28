-- Restore the two operational roles added outside the recorded migration history.
alter type public.practice_staff_role add value if not exists 'finance';
alter type public.practice_staff_role add value if not exists 'coder';
