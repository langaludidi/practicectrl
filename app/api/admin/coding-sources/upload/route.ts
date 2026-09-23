export async function POST(){
  return Response.json({
    error:"Deprecated source-upload path. Use the governed Source Register and practicectrl-source-upload."
  },{status:410,headers:{"cache-control":"no-store"}});
}
