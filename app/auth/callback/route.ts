import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function safeNext(value:string|null){return value&&value.startsWith("/")&&!value.startsWith("//")?value:"/dashboard";}

export async function GET(request:NextRequest){
  const code=request.nextUrl.searchParams.get("code");
  const next=safeNext(request.nextUrl.searchParams.get("next"));
  const target=new URL(next,request.url);
  if(!code){target.pathname="/login";target.searchParams.set("reason","missing_auth_code");return NextResponse.redirect(target);}
  const supabase=await createClient();
  const {error}=await supabase.auth.exchangeCodeForSession(code);
  if(error){const failed=new URL("/login",request.url);failed.searchParams.set("reason","invite_session_failed");return NextResponse.redirect(failed);}
  return NextResponse.redirect(target);
}
