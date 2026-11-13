import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const DOMAIN = "@expert-pr.app";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: u, error: ue } = await admin.auth.getUser(token);
  if (ue || !u?.user) return json({ error: "Not signed in" }, 401);
  const { data: me } = await admin.from("profiles").select("role").eq("id", u.user.id).maybeSingle();
  if (!me || me.role !== "admin") return json({ error: "Only the admin can manage users" }, 403);

  let b: any;
  try { b = await req.json(); } catch { return json({ error: "Bad request" }, 400); }

  const str = (x: unknown) => String(x ?? "").trim();
  const username = str(b.username).toLowerCase();
  const role = str(b.role);
  if (!["manager", "executive"].includes(role)) return json({ error: "Invalid role" }, 400);
  if (!/^[a-z0-9._-]{3,30}$/.test(username)) return json({ error: "Invalid username" }, 400);
  if (!str(b.name)) return json({ error: "Name is required" }, 400);

  if (b.action === "create") {
    const pw = String(b.password || "");
    if (pw.length < 6) return json({ error: "Password must have at least 6 characters" }, 400);
    const { data: dup } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
    if (dup) return json({ error: "That username is already taken" }, 409);
    const { data: c, error: ce } = await admin.auth.admin.createUser({
      email: username + DOMAIN, password: pw, email_confirm: true,
    });
    if (ce || !c?.user) return json({ error: ce?.message || "Could not create the user" }, 400);
    const { error: pe } = await admin.from("profiles").insert({
      id: c.user.id, username, name: str(b.name), email: str(b.email), phone: str(b.phone),
      role, manager_name: role === "executive" ? str(b.manager_name) : "", department: str(b.department),
    });
    if (pe) { await admin.auth.admin.deleteUser(c.user.id); return json({ error: pe.message }, 400); }
    return json({ ok: true, id: c.user.id });
  }

  if (b.action === "update") {
    const id = str(b.id);
    const { data: old } = await admin.from("profiles").select("*").eq("id", id).maybeSingle();
    if (!old || old.role === "admin") return json({ error: "User not found" }, 404);
    if (username !== old.username) {
      const { data: dup } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
      if (dup) return json({ error: "That username is already taken" }, 409);
    }
    const upd: Record<string, unknown> = {};
    if (username !== old.username) upd.email = username + DOMAIN;
    if (b.password) {
      if (String(b.password).length < 6) return json({ error: "Password must have at least 6 characters" }, 400);
      upd.password = String(b.password);
    }
    if (Object.keys(upd).length) {
      const { error: ae } = await admin.auth.admin.updateUserById(id, upd);
      if (ae) return json({ error: ae.message }, 400);
    }
    const { error: pe } = await admin.from("profiles").update({
      username, name: str(b.name), email: str(b.email), phone: str(b.phone),
      manager_name: old.role === "executive" ? str(b.manager_name) : "", department: str(b.department),
    }).eq("id", id);
    if (pe) return json({ error: pe.message }, 400);
    if (old.role === "manager" && old.name !== str(b.name)) {
      await admin.from("profiles").update({ manager_name: str(b.name) }).eq("manager_name", old.name).eq("role", "executive");
    }
    return json({ ok: true });
  }

  return json({ error: "Unknown action" }, 400);
});
