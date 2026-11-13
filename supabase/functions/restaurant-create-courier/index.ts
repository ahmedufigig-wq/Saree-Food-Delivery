import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function normalizePhone(value: unknown): { phone: string; digits: string } {
  const raw = String(value ?? "").trim();
  const phone = raw.replace(/[\s().-]/g, "");
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 7 || digits.length > 15) {
    throw new Error("رقم الهاتف غير صحيح. أدخل رقمًا من 7 إلى 15 رقمًا.");
  }
  return { phone: phone.startsWith("+") ? phone : digits, digits };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "طريقة الطلب غير مدعومة." });

  let createdUserId: string | null = null;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    let serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
    if (!serviceKey) {
      const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
      if (secretKeys) {
        try {
          const parsed = JSON.parse(secretKeys);
          serviceKey = parsed.default ?? Object.values(parsed)[0] ?? "";
        } catch {
          serviceKey = "";
        }
      }
    }
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return reply(500, { error: "إعدادات إنشاء الحساب غير مكتملة على الخادم." });
    }

    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token) return reply(401, { error: "يرجى تسجيل الدخول." });

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await callerClient.auth.getUser(token);
    if (authError || !authData.user) return reply(401, { error: "جلسة الدخول غير صالحة." });
    const ownerId = authData.user.id;

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json();
    const restaurantId = String(body.restaurant_id ?? "").trim();
    const fullName = String(body.full_name ?? "").trim();
    const password = String(body.password ?? "");
    const { phone, digits } = normalizePhone(body.phone);

    if (!restaurantId || fullName.length < 2 || fullName.length > 100) {
      return reply(400, { error: "أدخل اسم المندوب وحدد المطعم." });
    }
    if (password.length < 8 || password.length > 128) {
      return reply(400, { error: "كلمة المرور يجب ألا تقل عن 8 أحرف." });
    }

    const { data: owner, error: ownerError } = await admin
      .from("profiles")
      .select("role, approval_status, is_blocked")
      .eq("id", ownerId)
      .maybeSingle();
    if (ownerError) throw ownerError;
    if (!owner || owner.role !== "restaurant_owner" || owner.approval_status !== "approved" || owner.is_blocked) {
      return reply(403, { error: "إنشاء حسابات المندوبين متاح لصاحب المطعم المعتمد فقط." });
    }

    const { data: membership, error: membershipError } = await admin
      .from("restaurant_members")
      .select("restaurant_id")
      .eq("restaurant_id", restaurantId)
      .eq("user_id", ownerId)
      .maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return reply(403, { error: "ليس لديك صلاحية إضافة مندوب لهذا المطعم." });

    const internalEmail = `courier+${digits}@login.saree.invalid`;
    const { data: duplicateEmail, error: duplicateEmailError } = await admin
      .from("profiles").select("id").eq("phone", phone).maybeSingle();
    if (duplicateEmailError) throw duplicateEmailError;
    if (duplicateEmail) return reply(409, { error: "يوجد حساب مسجل برقم الهاتف هذا بالفعل." });

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: internalEmail,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        phone,
        requested_role: "courier",
      },
    });
    if (createError) {
      const message = createError.message.toLowerCase();
      if (message.includes("already") || message.includes("duplicate")) {
        return reply(409, { error: "يوجد حساب مسجل بهذه البيانات بالفعل." });
      }
      if (message.includes("password")) {
        return reply(400, { error: "كلمة المرور ضعيفة. استخدم كلمة مرور أقوى لا تقل عن 8 أحرف." });
      }
      throw createError;
    }
    if (!created.user) throw new Error("تعذر إنشاء حساب المندوب.");
    createdUserId = created.user.id;

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id, role, approval_status")
      .eq("id", createdUserId)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!profile || profile.role !== "courier" || profile.approval_status !== "pending") {
      throw new Error("لم يتم إنشاء ملف مندوب بحالة انتظار الاعتماد؛ أوقفنا العملية لحماية الحساب.");
    }

    const { error: teamError } = await admin.from("restaurant_couriers").upsert({
      restaurant_id: restaurantId,
      courier_id: createdUserId,
      is_active: true,
      added_by: ownerId,
    }, { onConflict: "restaurant_id,courier_id" });
    if (teamError) throw teamError;

    return reply(201, {
      user_id: createdUserId,
      full_name: fullName,
      phone,
      approval_status: "pending",
      message: "تم إنشاء حساب المندوب وربطه بالمطعم. سيبدأ العمل بعد موافقة الإدارة.",
    });
  } catch (error) {
    if (createdUserId) {
      try {
        const url = Deno.env.get("SUPABASE_URL") ?? "";
        const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        if (url && serviceKey) {
          const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
          await admin.auth.admin.deleteUser(createdUserId);
        }
      } catch {
        // Do not expose cleanup details or secrets to the caller.
      }
    }
    const message = error instanceof Error ? error.message : "حدث خطأ غير متوقع.";
    return reply(400, { error: message });
  }
});
