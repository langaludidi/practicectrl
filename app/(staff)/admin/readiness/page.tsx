import { redirect } from "next/navigation";
import { SectionHeader } from "@/components/SectionHeader";
import { ReleaseReadinessWorkspace } from "@/components/admin/ReleaseReadinessWorkspace";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";

const RELEASE_TARGET="0.34.0-dev.1";

export default async function ReleaseReadinessPage(){
  const staff=await requireStaffContext();
  if(!["practice_manager","system_admin","auditor"].includes(staff.role))redirect("/dashboard");
  const supabase=await createClient();
  const [
    {data:readiness,error:rErr},
    {data:dependencies,error:dErr},
    {data:runs,error:runErr},
    {data:probes,error:probeErr},
    {data:artifacts,error:artifactErr},
    {data:scenarios,error:scenarioErr}
  ]=await Promise.all([
    supabase.rpc("get_practicectrl_release_readiness",{p_practice_id:staff.practiceId}),
    supabase.rpc("get_release_dependency_register",{p_practice_id:staff.practiceId,p_release_version:RELEASE_TARGET}),
    supabase.from("release_validation_run").select("id,release_version,environment,status,started_at,completed_at,summary,created_at").eq("practice_id",staff.practiceId).eq("release_version",RELEASE_TARGET).order("created_at",{ascending:false}).limit(5),
    supabase.from("release_probe_snapshot").select("id,release_version,probe_version,checks,passed_count,failed_count,all_passed,created_at").eq("practice_id",staff.practiceId).eq("release_version",RELEASE_TARGET).order("created_at",{ascending:false}).limit(1),
    supabase.from("release_artifact_evidence").select("id,release_version,environment,deployment_provider,project_ref,deployment_ref,deployment_url,exact_origin,build_status,test_status,health_status,verified_at,created_at").eq("practice_id",staff.practiceId).eq("release_version",RELEASE_TARGET).order("created_at",{ascending:false}).limit(3),
    supabase.from("release_e2e_scenario_run").select("id,validation_run_id,release_version,scenario_key,status,started_at,completed_at,created_at").eq("practice_id",staff.practiceId).eq("release_version",RELEASE_TARGET).order("created_at",{ascending:false}).limit(3)
  ]);
  if(rErr)throw rErr;if(dErr)throw dErr;if(runErr)throw runErr;if(probeErr)throw probeErr;if(artifactErr)throw artifactErr;if(scenarioErr)throw scenarioErr;
  const latestRun=(runs||[])[0]||null;
  const latestScenario=(scenarios||[])[0]||null;
  const [{data:steps,error:stepErr},{data:checkpoints,error:checkpointErr}]=await Promise.all([
    latestRun?supabase.from("release_validation_step").select("id,run_id,step_key,sequence,label,status,notes,evidence,updated_at").eq("run_id",latestRun.id).order("sequence") : Promise.resolve({data:[],error:null}),
    latestScenario?supabase.from("release_e2e_scenario_checkpoint").select("id,run_id,sequence,checkpoint_key,label,status,notes,evidence,updated_at").eq("run_id",latestScenario.id).order("sequence") : Promise.resolve({data:[],error:null})
  ]);
  if(stepErr)throw stepErr;if(checkpointErr)throw checkpointErr;
  return <div className="space-y-6">
    <SectionHeader title="Release Readiness" body="PracticeCtrl 0.34 staging activation and controlled UAT. A green module is not release evidence: deployment, MFA, authoritative sources, build/test/health evidence and closed-loop UAT are separately verified."/>
    <ReleaseReadinessWorkspace
      practiceId={staff.practiceId}
      role={staff.role}
      releaseTarget={RELEASE_TARGET}
      readiness={(readiness||{}) as any}
      dependencies={(dependencies||{}) as any}
      runs={(runs||[]) as any}
      steps={(steps||[]) as any}
      latestProbe={(probes||[])[0] as any || null}
      artifacts={(artifacts||[]) as any}
      scenarios={(scenarios||[]) as any}
      checkpoints={(checkpoints||[]) as any}
    />
  </div>;
}
