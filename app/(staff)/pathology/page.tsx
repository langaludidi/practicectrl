import { PathologyWorkspace } from "@/components/pathology/PathologyWorkspace";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewPathology, canManagePathology, canSubmitPathology } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export default async function PathologyPage(){
  const staff=await requireStaffContext();
  if(!canViewPathology(staff.role)) return <p className="text-sm text-stone-600">Your role does not have access to pathology orders and results.</p>;
  const supabase=await createClient();
  const [
    {data:patients},{data:encounters},{data:providers},{data:connections},{data:capabilities},
    {data:orders},{data:orderItems},{data:results},{data:resultItems},{data:acks},{data:documents},
    {data:inbox},{data:specimens},{data:safetyCases},{data:releases},{data:followUps},
    {data:aiReviews},{data:readiness},{data:metrics},{data:aiReadiness}
  ]=await Promise.all([
    supabase.from("crm_patient").select("id,display_name,date_of_birth,source_patient_ref").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(500),
    supabase.from("practice_encounter").select("id,patient_id,service_date,encounter_type,status").eq("practice_id",staff.practiceId).order("service_date",{ascending:false}).limit(150),
    supabase.from("integration_provider").select("id,slug,name,lifecycle_status,authoritative_for,website_url").eq("provider_type","pathology_lab").order("name"),
    supabase.from("practice_integration_connection").select("id,provider_id,interface_id,environment,status").eq("practice_id",staff.practiceId),
    supabase.from("integration_adapter_capability").select("provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production").in("capability_code",["pathology_order_submit","pathology_result_receive","pathology_result_query","pathology_report_document"]),
    supabase.from("pathology_order").select("id,patient_id,encounter_id,provider_id,order_number,status,delivery_mode,transport_status,priority,order_category,treating_practitioner_user_id,clinical_indication,external_order_ref,ordered_at,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(150),
    supabase.from("pathology_order_item").select("id,order_id,concept_id,test_code,test_name,specimen_type,status").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("pathology_result").select("id,order_id,patient_id,provider_id,status,overall_flag,external_result_ref,accession_number,received_at,reported_at,report_comment,version_no,correction_of_result_id,is_current,superseded_by_result_id").eq("practice_id",staff.practiceId).order("received_at",{ascending:false}).limit(200),
    supabase.from("pathology_result_item").select("id,result_id,order_item_id,concept_id,test_code,test_name,value_type,value_numeric,value_text,unit,reference_range,flag,observation_at,comment").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("pathology_result_acknowledgement").select("result_id,acknowledgement_status,follow_up_plan,patient_contacted_at,acknowledged_at").eq("practice_id",staff.practiceId),
    supabase.from("pathology_result_document").select("id,result_id,storage_path,original_filename,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}),
    supabase.from("pathology_result_inbox").select("id,provider_id,patient_id,matched_order_id,external_patient_ref,external_order_ref,external_result_ref,accession_number,status,overall_flag_hint,summary,received_at,match_confidence,match_basis").eq("practice_id",staff.practiceId).order("received_at",{ascending:false}).limit(100),
    supabase.from("pathology_specimen").select("id,order_id,patient_id,specimen_identifier,specimen_type,body_site,status,collected_at,received_by_lab_at,rejection_reason").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}),
    supabase.from("pathology_safety_case").select("id,result_id,severity,status,sla_due_at,escalation_level,assigned_user_id,last_escalated_at").eq("practice_id",staff.practiceId).order("sla_due_at"),
    supabase.from("pathology_result_release").select("result_id,status,hold_reason,release_after,approved_at,released_at").eq("practice_id",staff.practiceId),
    supabase.from("pathology_follow_up_action").select("id,result_id,action_type,status,due_at,details,appointment_request_id,completed_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}),
    supabase.from("pathology_ai_review").select("id,result_id,status,input_mode,source_document_count,model_id,summary,key_findings,abnormal_findings,critical_findings,extracted_observations,clinician_attention,limitations,confidence,created_at,completed_at,reviewed_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(300),
    supabase.rpc("get_pathology_readiness",{p_practice_id:staff.practiceId}),
    supabase.rpc("get_pathology_metrics",{p_practice_id:staff.practiceId,p_window_days:30}),
    supabase.rpc("get_pathology_ai_readiness",{p_practice_id:staff.practiceId}),
  ]);

  return <div className="space-y-6">
    <SectionHeader title="Pathology" body="Closed-loop pathology ordering, specimen tracking, result review, AI-assisted report summarisation, correction history, longitudinal trends, follow-up and governed patient release."/>
    <PathologyWorkspace practiceId={staff.practiceId} role={staff.role} userId={staff.userId} canManage={canManagePathology(staff.role)} canSubmit={canSubmitPathology(staff.role)} patients={(patients||[]) as any} encounters={(encounters||[]) as any} providers={(providers||[]) as any} connections={(connections||[]) as any} capabilities={(capabilities||[]) as any} orders={(orders||[]) as any} orderItems={(orderItems||[]) as any} results={(results||[]) as any} resultItems={(resultItems||[]) as any} acknowledgements={(acks||[]) as any} documents={(documents||[]) as any} inbox={(inbox||[]) as any} specimens={(specimens||[]) as any} safetyCases={(safetyCases||[]) as any} releases={(releases||[]) as any} followUps={(followUps||[]) as any} aiReviews={(aiReviews||[]) as any} readiness={(readiness||{}) as any} metrics={(metrics||{}) as any} aiReadiness={(aiReadiness||{}) as any}/>
  </div>;
}
