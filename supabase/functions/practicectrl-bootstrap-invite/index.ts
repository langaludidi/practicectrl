import { createClient } from "npm:@supabase/supabase-js@2.57.4";

function adminClient(){
  const url=Deno.env.get("SUPABASE_URL")!;
  const sj=Deno.env.get("SUPABASE_SECRET_KEYS");
  const secret=sj?JSON.parse(sj).default:Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!secret)throw new Error("Supabase admin environment is unavailable");
  return createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
}
async function sha256(value:string){const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return[...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,"0")).join("");}
function constantTimeEqual(a:string,b:string){if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
function safeOrigin(value:string){try{const u=new URL(value);return u.protocol==="https:"&&u.origin===value&&u.username===""&&u.password===""&&!/^(localhost|127\.|0\.0\.0\.0|\[::1\])/.test(u.hostname);}catch{return false;}}
function json(body:unknown,status=200,origin?:string){return new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store","access-control-allow-origin":origin||"null","access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS","vary":"Origin","referrer-policy":"no-referrer"}});}

Deno.serve(async(req)=>{
  const admin=adminClient();
  const requestOrigin=req.headers.get("origin")||"";
  if(req.method==="OPTIONS"){
    if(!safeOrigin(requestOrigin))return json({error:"HTTPS staging origin required."},403);
    return json({ok:true},200,requestOrigin);
  }
  if(req.method!=="POST")return json({error:"Method not allowed."},405,requestOrigin||undefined);
  if(!safeOrigin(requestOrigin))return json({error:"Bootstrap must run from the deployed HTTPS PracticeCtrl application."},403);

  const body=await req.json().catch(()=>({}));
  const action=String(body?.action||"invite");
  const tenantSlug=String(body?.tenantSlug||"").trim().toLowerCase();
  const email=String(body?.email||"").trim().toLowerCase();
  const suppliedToken=String(body?.bootstrapToken||"");
  if(!tenantSlug)return json({error:"Tenant identifier is required."},400,requestOrigin);

  const{data:practice}=await admin.from("practice").select("id,name,tenant_slug,active").eq("tenant_slug",tenantSlug).eq("active",true).maybeSingle();
  if(!practice)return json({error:"Tenant bootstrap is unavailable."},404,requestOrigin);
  if(suppliedToken.length<24)return json({error:"Invalid bootstrap secret."},403,requestOrigin);

  const{data:control,error:controlError}=await admin.from("practice_bootstrap_control").select("token_sha256,expires_at,consumed_at,failed_attempts,last_failed_at,locked_until").eq("practice_id",practice.id).maybeSingle();
  if(controlError||!control)return json({error:"Bootstrap is not configured."},503,requestOrigin);
  if(control.consumed_at)return json({error:"Bootstrap has already been consumed."},409,requestOrigin);
  if(new Date(control.expires_at).getTime()<=Date.now())return json({error:"Bootstrap secret has expired."},410,requestOrigin);
  if(control.locked_until&&new Date(control.locked_until).getTime()>Date.now())return json({error:"Too many invalid bootstrap attempts. Try again later."},429,requestOrigin);

  const suppliedHash=await sha256(suppliedToken);
  if(!constantTimeEqual(suppliedHash,control.token_sha256)){
    const{data:attempt}=await admin.rpc("register_bootstrap_token_attempt",{p_practice_id:practice.id,p_success:false});
    if(attempt?.locked)return json({error:"Too many invalid bootstrap attempts. Try again later."},429,requestOrigin);
    return json({error:"Invalid bootstrap secret."},403,requestOrigin);
  }
  await admin.rpc("register_bootstrap_token_attempt",{p_practice_id:practice.id,p_success:true});

  const{count:staffCount,error:countError}=await admin.from("practice_staff_member").select("user_id",{count:"exact",head:true}).eq("practice_id",practice.id);
  if(countError)return json({error:"Could not verify tenant bootstrap state."},500,requestOrigin);
  if((staffCount||0)>0)return json({error:"Bootstrap is closed because staff already exist."},409,requestOrigin);

  const{data:existingOrigin}=await admin.from("practice_app_origin").select("origin,active").eq("practice_id",practice.id).eq("environment","staging").maybeSingle();
  if(action==="register_origin"){
    const requestedOrigin=String(body?.origin||"");
    if(requestedOrigin!==requestOrigin||!safeOrigin(requestedOrigin))return json({error:"The submitted staging origin must match the browser origin exactly."},400,requestOrigin);
    if(existingOrigin?.active&&existingOrigin.origin!==requestOrigin)return json({error:"A different staging origin is already registered. Rotate it from an authenticated administration session."},409,requestOrigin);
    const{error:originError}=await admin.from("practice_app_origin").upsert({practice_id:practice.id,environment:"staging",origin:requestOrigin,active:true,updated_at:new Date().toISOString()},{onConflict:"practice_id,environment"});
    if(originError)return json({error:"Could not register the PracticeCtrl staging origin."},500,requestOrigin);
    await admin.from("practice_access_event").insert({practice_id:practice.id,event_type:"bootstrap_staging_origin_registered",metadata:{origin:requestOrigin,tenant_slug:tenantSlug}});
    return json({ok:true,origin:requestOrigin,message:"Staging origin registered for first-administrator bootstrap."},200,requestOrigin);
  }

  if(action!=="invite")return json({error:"Unsupported bootstrap action."},400,requestOrigin);
  const allowedOrigin=existingOrigin?.active?String(existingOrigin.origin):"";
  if(!allowedOrigin)return json({error:"Register this staging origin first."},409,requestOrigin);
  if(requestOrigin!==allowedOrigin)return json({error:"Origin not allowed."},403,allowedOrigin);
  if(!/^\S+@\S+\.\S+$/.test(email))return json({error:"Enter a valid email address."},400,allowedOrigin);

  const now=new Date().toISOString();
  await admin.from("practice_staff_invitation").update({status:"expired"}).eq("practice_id",practice.id).eq("invitation_kind","bootstrap_admin").eq("status","pending").lt("expires_at",now);
  const inviteId=crypto.randomUUID();
  const expiresAt=new Date(Date.now()+48*60*60*1000).toISOString();
  const{data:known}=await admin.from("practice_staff_member").select("user_id").ilike("email",email).limit(1).maybeSingle();
  const{error:insertError}=await admin.from("practice_staff_invitation").insert({id:inviteId,practice_id:practice.id,email,email_normalized:email,role:"system_admin",invitation_kind:"bootstrap_admin",status:"pending",expires_at:expiresAt,invited_user_id:known?.user_id||null,sent_at:known?.user_id?now:null});
  if(insertError)return json({error:"A pending bootstrap invitation already exists or could not be created."},409,allowedOrigin);
  if(known?.user_id){
    await admin.from("practice_access_event").insert({practice_id:practice.id,event_type:"bootstrap_invite_created_existing_user",subject_user_id:known.user_id,invitation_id:inviteId,metadata:{role:"system_admin"}});
    return json({message:"First-administrator invitation created for an existing PracticeCtrl user. They can sign in and accept it from Practice invitations."},200,allowedOrigin);
  }
  const next="/onboarding/accept?invite="+encodeURIComponent(inviteId);
  const redirectTo=allowedOrigin+"/auth/callback?next="+encodeURIComponent(next);
  const{data,error:inviteError}=await admin.auth.admin.inviteUserByEmail(email,{redirectTo,data:{practicectrl_invite_id:inviteId,practicectrl_tenant_slug:tenantSlug}});
  if(inviteError||!data.user){
    await admin.from("practice_staff_invitation").update({status:"send_failed"}).eq("id",inviteId);
    await admin.from("practice_access_event").insert({practice_id:practice.id,event_type:"invite_send_failed",invitation_id:inviteId,metadata:{invitation_kind:"bootstrap_admin"}});
    return json({error:"Supabase could not send the invitation."},502,allowedOrigin);
  }
  await admin.from("practice_staff_invitation").update({invited_user_id:data.user.id,sent_at:now}).eq("id",inviteId);
  await admin.from("practice_access_event").insert({practice_id:practice.id,event_type:"bootstrap_invite_sent",subject_user_id:data.user.id,invitation_id:inviteId,metadata:{role:"system_admin"}});
  return json({message:"First-administrator invitation sent. It expires in 48 hours."},200,allowedOrigin);
});