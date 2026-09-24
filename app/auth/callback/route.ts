import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function safeNext(value:string|null){return value&&value.startsWith("/")&&!value.startsWith("//")?value:"/dashboard";}

export async function GET(request:NextRequest){
  const code=request.nextUrl.searchParams.get("code");
  const next=safeNext(request.nextUrl.searchParams.get("next"));
  const target=new URL(next,request.url);
  const recovery=new URL("/auth/recover",request.url);
  const invite=target.searchParams.get("invite");
  if(invite&&/^[0-9a-f-]{36}$/i.test(invite)) recovery.searchParams.set("invite",invite);
  recovery.searchParams.set("reason","link_unusable");
  // In a recovery implicit flow, the session is in the URL fragment. Browsers
  // carry that fragment to this same-origin redirect; the server cannot read it.
  if(!code&&target.pathname==="/auth/set-password"){
    const finish=new URL("/auth/finish",request.url);
    if(invite&&/^[0-9a-f-]{36}$/i.test(invite)) finish.searchParams.set("invite",invite);
    return NextResponse.redirect(finish);
  }
  if(!code) return NextResponse.redirect(recovery);
  const supabase=await createClient();
  const {error}=await supabase.auth.exchangeCodeForSession(code);
  if(error) return NextResponse.redirect(recovery);
  return NextResponse.redirect(target);
}
