import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"GET, POST, OPTIONS"};
const ADMIN_ID="24414e46-0e3c-4979-b5c5-08dad6b39158";
Deno.serve(async(req:Request)=>{
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(!["GET","POST"].includes(req.method))return reply({error:"Method not allowed"},405);
 const url=Deno.env.get("SUPABASE_URL"),secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),anon=Deno.env.get("SUPABASE_ANON_KEY");
 if(!url||!secret||!anon)return reply({error:"Server configuration missing"},500);
 const auth=req.headers.get("Authorization");if(!auth)return reply({error:"Sign in required"},401);
 const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:authError}=await userClient.auth.getUser();
 if(authError||!user||user.id!==ADMIN_ID)return reply({error:"Not authorized"},403);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 if(req.method==="GET"){const {data,error}=await admin.from("businesses").select("id,name,slug,status,email,phone,created_at,providers(id,business_name,category,active)").order("created_at",{ascending:false});return error?reply({error:error.message},400):reply({businesses:data??[]});}
 let body:Record<string,unknown>;try{body=await req.json()}catch{return reply({error:"Invalid JSON"},400)}
 const name=String(body.business_name??"").trim(),category=String(body.category??"").trim(),email=String(body.owner_email??"").trim().toLowerCase(),phone=String(body.phone??"").trim(),zip=String(body.zip??"").trim(),area=String(body.service_area??"").trim(),services=String(body.services??"").trim(),radiusRaw=Number(body.service_radius_miles??55),radius=Number.isInteger(radiusRaw)&&radiusRaw>=1&&radiusRaw<=250?radiusRaw:55;
 if(!name||!category||!email||! /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return reply({error:"Business name, valid owner email, and category are required."},400);
 const slug=name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,48)+"-"+crypto.randomUUID().slice(0,8);
 const {data:business,error:be}=await admin.from("businesses").insert({name,slug,status:"active",email,phone}).select("id,name,slug").single();
 if(be)return reply({error:be.message},400);
 const {data:invite,error:ie}=await admin.auth.admin.inviteUserByEmail(email,{data:{business_name:name,invited_by:"LocalMatch"}});
 if(ie||!invite.user){await admin.from("businesses").delete().eq("id",business.id);return reply({error:ie?.message??"Invitation failed"},400)}
 const {error:me}=await admin.from("business_members").insert({business_id:business.id,user_id:invite.user.id,role:"owner"});
 if(me){await admin.auth.admin.deleteUser(invite.user.id);await admin.from("businesses").delete().eq("id",business.id);return reply({error:me.message},400)}
 const {error:pe}=await admin.from("providers").insert({business_id:business.id,business_name:name,category,email,phone,zip:zip||null,service_area:area||null,services:services||null,service_radius_miles:radius,active:true});
 if(pe){await admin.from("business_members").delete().eq("business_id",business.id);await admin.auth.admin.deleteUser(invite.user.id);await admin.from("businesses").delete().eq("id",business.id);return reply({error:pe.message},400)}
 return reply({success:true,business,invited_email:email,message:"Business created and invitation sent."},201);
});