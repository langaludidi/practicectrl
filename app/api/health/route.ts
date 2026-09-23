import { NextResponse } from "next/server";
const VERSION="0.34.0-dev.1";
export const dynamic="force-dynamic";
export async function GET(){return NextResponse.json({service:"PracticeCtrl",version:VERSION,status:"ok",environment:process.env.VERCEL_ENV||process.env.NODE_ENV||"unknown",timestamp:new Date().toISOString()},{status:200,headers:{"Cache-Control":"no-store","X-Robots-Tag":"noindex, nofollow"}});}
