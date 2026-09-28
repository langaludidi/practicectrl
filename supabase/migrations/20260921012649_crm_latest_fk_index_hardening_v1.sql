
create index if not exists crm_patient_match_patient_a_idx
  on public.crm_patient_match_candidate(patient_a_id);
create index if not exists crm_patient_match_patient_b_idx
  on public.crm_patient_match_candidate(patient_b_id);
create index if not exists crm_scheme_membership_option_idx
  on public.crm_patient_scheme_membership(medical_scheme_option_id)
  where medical_scheme_option_id is not null;
create index if not exists crm_scheme_membership_practice_idx
  on public.crm_patient_scheme_membership(practice_id,membership_status);

