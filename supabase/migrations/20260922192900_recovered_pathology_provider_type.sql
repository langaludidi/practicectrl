-- The original pathology provider enum change was not recorded in migration history.
alter type public.integration_provider_type add value if not exists 'pathology_lab';
