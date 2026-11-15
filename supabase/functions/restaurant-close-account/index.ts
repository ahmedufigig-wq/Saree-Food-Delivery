import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return new Response(JSON.stringify({ error: "يجب تسجيل الدخول أولاً" }), {
    status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

  try {
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) throw new Error("تعذر التحقق من هوية الحساب");
    const userId = authData.user.id;

    const { data: profile, error: profileError } = await admin
      .from("profiles").select("role").eq("id", userId).maybeSingle();
    if (profileError || profile?.role !== "restaurant_owner") {
      return new Response(JSON.stringify({ error: "هذا الإجراء متاح لصاحب المطعم فقط" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: memberships, error: membershipError } = await admin
      .from("restaurant_members").select("restaurant_id").eq("user_id", userId);
    if (membershipError) throw membershipError;
    const ids = [...new Set((memberships ?? []).map((row) => row.restaurant_id).filter(Boolean))];
    if (ids.length) {
      const { error } = await admin.from("restaurants").update({ is_active: false }).in("id", ids);
      if (error) throw error;
    }

    const { error: blockError } = await admin.from("profiles")
      .update({ is_blocked: true, approval_status: "rejected", approval_note: "تم إغلاق الحساب نهائياً بناءً على طلب صاحبه." })
      .eq("id", userId);
    if (blockError) throw blockError;

    if (authData.user.email) {
      const closedEmail = `closed+${userId}@saree-account.invalid`;
      const randomPassword = `${crypto.randomUUID()}A9!${crypto.randomUUID()}`;
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(userId, {
        email: closedEmail, email_confirm: true, password: randomPassword,
      });
      if (authUpdateError) {
        await admin.from("profiles").update({ is_blocked: false, approval_status: "approved", approval_note: null }).eq("id", userId);
        throw authUpdateError;
      }
    }

    return new Response(JSON.stringify({ success: true, message: "تم إغلاق الحساب وإيقاف المطعم. يمكن إنشاء حساب جديد." }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "تعذر إغلاق الحساب" }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
