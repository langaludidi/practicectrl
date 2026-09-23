import { MedicinesWorkspace } from "@/components/medicines/MedicinesWorkspace";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewMedicines, canManageMedicines, canPrescribeMedicines } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

const AI_CAPABILITIES = [
  "medicines.reconciliation_extraction",
  "medicines.prescription_structuring",
  "medicines.safety_explanation",
  "medicines.patient_instructions",
  "medicines.monitoring_summary",
] as const;

export default async function MedicinesPage(){
  const staff=await requireStaffContext();
  if(!canViewMedicines(staff.role)) return <p className="text-sm text-stone-600">Your role does not have access to medicines and prescribing workflows.</p>;
  const supabase=await createClient();

  const [
    {data:patients},{data:allergies},{data:medications},{data:reconSessions},{data:reconItems},
    {data:prescriptions},{data:prescriptionItems},{data:assessments},{data:findings},{data:aiReviews},
    {data:sourceFiles},{data:providers},{data:connections},{data:capabilities},{data:readiness},{data:metrics},
    ...aiReadinessResults
  ]=await Promise.all([
    supabase.from("crm_patient").select("id,display_name,date_of_birth,source_patient_ref").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(500),
    supabase.from("patient_allergy").select("id,patient_id,ingredient_id,substance_text,reaction_text,severity,status,source,recorded_at").eq("practice_id",staff.practiceId).order("recorded_at",{ascending:false}).limit(500),
    supabase.from("patient_medication").select("id,patient_id,product_id,ingredient_id,medication_name,dose_text,route,frequency,indication_text,status,start_date,end_date,source,reconciled,reconciled_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(1000),
    supabase.from("medication_reconciliation_session").select("id,patient_id,encounter_id,status,source_context,started_at,completed_at").eq("practice_id",staff.practiceId).order("started_at",{ascending:false}).limit(200),
    supabase.from("medication_reconciliation_item").select("id,session_id,existing_medication_id,product_id,ingredient_id,medication_name,dose_text,route,frequency,proposed_action,source,confidence,evidence_text,review_status,reviewed_at").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("prescription").select("id,patient_id,encounter_id,status,issue_mode,provider_id,indication_text,general_instructions,prescriber_user_id,created_at,safety_assessed_at,clinician_approved_at,external_prescription_ref,transmitted_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(250),
    supabase.from("prescription_item").select("id,prescription_id,product_id,ingredient_id,medication_name,nappi_code_snapshot,dose_value,dose_unit,route,frequency,duration_text,quantity,quantity_unit,repeats,prn,instructions,source").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("prescription_safety_assessment").select("id,prescription_id,assessment_version,status,blocking_count,warning_count,reference_ready,interaction_data_ready,assessed_at").eq("practice_id",staff.practiceId).order("assessed_at",{ascending:false}).limit(500),
    supabase.from("prescription_safety_finding").select("id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail,deterministic").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("medicines_ai_review").select("id,patient_id,prescription_id,reconciliation_session_id,capability_key,status,input_mode,model_id,summary,structured_output,limitations,confidence,created_at,completed_at,reviewed_at,applied_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(300),
    supabase.from("medicines_ai_source_file").select("id,patient_id,reconciliation_session_id,prescription_id,storage_path,original_filename,content_type,sha256,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(200),
    supabase.from("integration_provider").select("id,slug,name,lifecycle_status,website_url").in("slug",["emguidance-script"]).order("name"),
    supabase.from("practice_integration_connection").select("id,provider_id,interface_id,environment,status").eq("practice_id",staff.practiceId),
    supabase.from("integration_adapter_capability").select("provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production").in("capability_code",["drug_interaction_check","prescription_transmit","prescription_status","pharmacy_directory"]),
    supabase.rpc("get_medicines_readiness",{p_practice_id:staff.practiceId}),
    supabase.rpc("get_medicines_metrics",{p_practice_id:staff.practiceId,p_window_days:30}),
    ...AI_CAPABILITIES.map(capability=>supabase.rpc("get_medicines_ai_readiness",{p_practice_id:staff.practiceId,p_capability_key:capability})),
  ]);

  const aiReadiness=Object.fromEntries(AI_CAPABILITIES.map((capability,index)=>[capability,aiReadinessResults[index]?.data||{}]));

  return <div className="space-y-6">
    <SectionHeader title="Medicines" body="Medication history, reconciliation, deterministic prescribing safety, governed medicine references, e-prescribing readiness and clinician-controlled AI assistance."/>
    <MedicinesWorkspace
      practiceId={staff.practiceId}
      role={staff.role}
      userId={staff.userId}
      canManage={canManageMedicines(staff.role)}
      canPrescribe={canPrescribeMedicines(staff.role)}
      patients={(patients||[]) as any}
      allergies={(allergies||[]) as any}
      medications={(medications||[]) as any}
      reconciliationSessions={(reconSessions||[]) as any}
      reconciliationItems={(reconItems||[]) as any}
      prescriptions={(prescriptions||[]) as any}
      prescriptionItems={(prescriptionItems||[]) as any}
      assessments={(assessments||[]) as any}
      findings={(findings||[]) as any}
      aiReviews={(aiReviews||[]) as any}
      sourceFiles={(sourceFiles||[]) as any}
      providers={(providers||[]) as any}
      connections={(connections||[]) as any}
      capabilities={(capabilities||[]) as any}
      readiness={(readiness||{}) as any}
      metrics={(metrics||{}) as any}
      aiReadiness={aiReadiness as any}
    />
  </div>;
}
