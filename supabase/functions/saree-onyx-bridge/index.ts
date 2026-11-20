import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });
const hex = (bytes: ArrayBuffer) =>
  [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
const hash = async (value: string) =>
  hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const authHeader = req.headers.get("authorization") || "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // Provisioning is an authenticated admin-only action. The raw token is returned once.
  if (req.method === "POST" && url.pathname.endsWith("/provision")) {
    if (!bearer) return json({ error: "admin_login_required" }, 401);
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: "Bearer " + bearer } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(bearer);
    if (userError || !userData.user) return json({ error: "invalid_user_session" }, 401);
    const { data: profile } = await admin.from("profiles").select("role").eq("id", userData.user.id).maybeSingle();
    if (profile?.role !== "admin") return json({ error: "admin_only" }, 403);
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
    const restaurantId = String(body.restaurant_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(restaurantId)) return json({ error: "invalid_restaurant_id" }, 400);
    const { data: restaurant } = await admin.from("restaurants").select("id,name").eq("id", restaurantId).maybeSingle();
    if (!restaurant) return json({ error: "restaurant_not_found" }, 404);
    const rawToken = "saree_onyx_" + crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
    const tokenHash = await hash(rawToken);
    const { data: connector, error } = await admin.from("pos_connectors").upsert({
      restaurant_id: restaurantId,
      vendor: "yemensoft_onyx_pro",
      mode: "local_bridge",
      status: "active",
      token_hash: tokenHash,
      vendor_version: String(body.vendor_version || "unknown").slice(0, 80),
      company_code: body.company_code ? String(body.company_code).slice(0, 80) : null,
      branch_code: body.branch_code ? String(body.branch_code).slice(0, 80) : null,
      pos_terminal_code: body.pos_terminal_code ? String(body.pos_terminal_code).slice(0, 80) : null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "restaurant_id" }).select("id,restaurant_id,vendor,mode,status").single();
    if (error) return json({ error: "connector_provision_failed" }, 500);
    return json({
      connector,
      bridge_token: rawToken,
      bridge_url: supabaseUrl + "/functions/v1/saree-onyx-bridge",
      warning: "Copy the token now. It is shown once; store it securely on the restaurant Windows PC.",
    }, 201);
  }

  // All other routes require a per-restaurant bridge token, never a Supabase service key.
  if (!bearer || bearer.length < 32) return json({ error: "missing_bridge_token" }, 401);
  const digest = await hash(bearer);
  const { data: connector, error: authError } = await admin
    .from("pos_connectors")
    .select("id,restaurant_id,vendor,mode,status")
    .eq("token_hash", digest)
    .eq("status", "active")
    .maybeSingle();
  if (authError || !connector) return json({ error: "invalid_or_inactive_bridge_token" }, 401);
  await admin.from("pos_connectors")
    .update({ last_seen_at: new Date().toISOString(), last_error: null })
    .eq("id", connector.id);

  if (req.method === "GET" && url.pathname.endsWith("/jobs")) {
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || "10"), 1), 25);
    const { data, error } = await admin.from("pos_jobs")
      .select("id,event_id,event_type,payload,attempts,created_at")
      .eq("connector_id", connector.id).in("status", ["pending", "failed"])
      .order("created_at", { ascending: true }).limit(limit);
    if (error) return json({ error: "job_poll_failed" }, 500);
    const ids = (data || []).map((job) => job.id);
    if (ids.length) {
      const { error: lockError } = await admin.from("pos_jobs")
        .update({ status: "processing", attempts: 1 })
        .in("id", ids).eq("connector_id", connector.id).eq("status", "pending");
      if (lockError) return json({ error: "job_lock_failed" }, 500);
    }
    return json({ jobs: (data || []).map((job) => ({
      id: job.id, payload: { ...job.payload, event_id: job.event_id },
      event_type: job.event_type, attempts: job.attempts, created_at: job.created_at,
    })) });
  }

  const match = url.pathname.match(/\/jobs\/([0-9a-f-]+)\/ack$/i);
  if (req.method === "POST" && match) {
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
    const status = String(body.status || "");
    if (!["printed", "accepted", "failed"].includes(status)) return json({ error: "invalid_status" }, 400);
    const update: Record<string, unknown> = {
      status, updated_at: new Date().toISOString(), acknowledged_at: new Date().toISOString(),
      last_error: status === "failed" ? String(body.error || "bridge_failed").slice(0, 1000) : null,
      vendor_reference: body.vendor_reference ? String(body.vendor_reference).slice(0, 200) : null,
    };
    const { data, error } = await admin.from("pos_jobs").update(update)
      .eq("id", match[1]).eq("connector_id", connector.id)
      .select("id,status").maybeSingle();
    if (error) return json({ error: "job_ack_failed" }, 500);
    if (!data) return json({ error: "job_not_found" }, 404);
    return json({ ok: true, job: data });
  }
  return json({ error: "not_found" }, 404);
});
