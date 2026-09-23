import { SectionHeader } from "@/components/SectionHeader";
import { MetricCard } from "@/components/MetricCard";
import { IntakeWorkspace } from "@/components/intake/IntakeWorkspace";
import { IntakeReviewPanel } from "@/components/intake/IntakeReviewPanel";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";

export default async function IntakePage(){
 const staff=await requireStaffContext(); const supabase=await createClient();
 const [{data:sessions},{data:appointments},{data:patients},{data:candidates},{data:documents},{data:mergeDecisions}]=await Promise.all([
  supabase.from("patient_intake_session").select("id,appointment_id,existing_patient_id,source,status,patient_display_name,patient_phone_hint,patient_email_hint,opened_at,submitted_at,created_at,token_expires_at,submitted_json,review_notes").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(200),
  supabase.from("practice_appointment").select("id,appointment_number,patient_id,starts_at,status").eq("practice_id",staff.practiceId).gte("starts_at",new Date(Date.now()-86400000).toISOString()).order("starts_at").limit(300),
  supabase.from("crm_patient").select("id,display_name,first_name,last_name,date_of_birth,primary_phone,primary_email").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(1000),
  supabase.from("patient_intake_match_candidate").select("id,intake_session_id,patient_id,match_score,match_reasons,status").eq("practice_id",staff.practiceId).order("match_score",{ascending:false}).limit(1000),
  supabase.from("patient_intake_document").select("id,intake_session_id,document_type,original_filename,mime_type,file_size_bytes,verification_status,verification_notes,uploaded_at").eq("practice_id",staff.practiceId).order("uploaded_at",{ascending:false}).limit(1000),
  supabase.from("patient_intake_merge_decision").select("intake_session_id,patient_id,field_key,current_value,submitted_value,decision,decided_at").eq("practice_id",staff.practiceId).limit(2000)
 ]);
 const rows=(sessions||[]) as any[]; const submitted=rows.filter(x=>x.status==="submitted"||x.status==="under_review").length; const waiting=rows.filter(x=>["invited","opened","in_progress"].includes(x.status)).length; const complete=rows.filter(x=>["verified","applied"].includes(x.status)).length;
 return <div className="space-y-6"><SectionHeader title="Patient Intake & Registration" body="Secure online, tablet and paper-backed registration. Intake stays separate from the patient master until reception verifies identity, consent and possible duplicates."/><section className="grid gap-3 sm:grid-cols-3"><MetricCard label="Awaiting patient" value={String(waiting)} note="Invited, opened or in progress"/><MetricCard label="Needs review" value={String(submitted)} note="Submitted registrations"/><MetricCard label="Verified / applied" value={String(complete)} note="Completed intake workflow"/></section><IntakeReviewPanel practiceId={staff.practiceId} sessions={rows.filter(x=>["submitted","under_review","validation_required"].includes(x.status)) as any} patients={(patients||[]) as any} candidates={(candidates||[]) as any} documents={(documents||[]) as any} mergeDecisions={(mergeDecisions||[]) as any}/><IntakeWorkspace practiceId={staff.practiceId} appointments={(appointments||[]) as any} patients={(patients||[]) as any} sessions={rows}/></div>
}
