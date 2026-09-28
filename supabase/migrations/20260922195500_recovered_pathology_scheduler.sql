-- Restore the private safety escalation scheduler validated by v0.30.1.
select cron.schedule('practicectrl-pathology-safety-10m','*/10 * * * *','select private.process_pathology_safety_escalations();');
