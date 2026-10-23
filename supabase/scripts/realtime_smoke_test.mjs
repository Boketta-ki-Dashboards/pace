#!/usr/bin/env node
// Ende-zu-Ende-Prüfung der Chat-Echtzeit gegen den LOKALEN Supabase-Stack (Realtime-Server + Policies).
//
// Warum ein eigenes Skript: Der Swift-Client nutzt URLSessionWebSocketTask; unter Linux steckt dahinter libcurl, das
// in Ubuntu 24.04 ohne WebSocket-Unterstützung gebaut ist. Die Swift-Integrationstests prüfen Echtzeit deshalb nur
// auf Apple-Plattformen. Dieses Skript spricht das Realtime-Protokoll direkt (WebSocket von Node ≥ 22) und prüft:
//   1. Teilnehmer dürfen den privaten Kanal chat:<conversation_id> und ihren Kanal user:<public_id> abonnieren.
//   2. Fremde werden bei beiden abgewiesen.
//   3. Eine neue Nachricht löst Hinweise auf beiden Kanälen aus – ohne Nachrichteninhalt.
//   4. Bearbeiten (message_updated) und Anpinnen (pins_changed) melden sich auf chat:<conversation_id> – ebenfalls
//      ohne Inhalt (Migration 20261023100100).
//
// Aufruf (nach `supabase start`):
//   eval "$(supabase status -o env)"
//   PACE_SUPABASE_URL="$API_URL" PACE_SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}" \
//     node supabase/scripts/realtime_smoke_test.mjs
//
// Nur für lokale Stacks gedacht: Das Skript legt anonyme Testnutzer an.

const baseURL = process.env.PACE_SUPABASE_URL;
const apiKey = process.env.PACE_SUPABASE_PUBLISHABLE_KEY;
if (!baseURL || !apiKey) {
  console.error("PACE_SUPABASE_URL und PACE_SUPABASE_PUBLISHABLE_KEY fehlen.");
  process.exit(2);
}
const host = new URL(baseURL).hostname;
if (!["127.0.0.1", "localhost", "::1"].includes(host)) {
  console.error(`Abbruch: ${host} ist kein lokaler Stack.`);
  process.exit(2);
}

const TIMEOUT_MS = 10_000;
let failures = 0;

function check(condition, message) {
  if (condition) {
    console.log(`ok - ${message}`);
  } else {
    failures += 1;
    console.log(`not ok - ${message}`);
  }
}

async function request(path, { method = "POST", token, body, headers = {} } = {}) {
  const response = await fetch(new URL(path, baseURL), {
    method,
    headers: {
      apikey: apiKey,
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${method} ${path}: HTTP ${response.status} ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

const rpc = (token, name, params = {}) => request(`/rest/v1/rpc/${name}`, { token, body: params });

async function newUser(name) {
  const session = await request("/auth/v1/signup", { body: {} });
  const username = `${name}_${crypto.randomUUID().slice(0, 8)}`;
  const [profile] = await request("/rest/v1/profiles", {
    token: session.access_token,
    body: { id: session.user.id, username, display_name: name },
    headers: { Prefer: "return=representation" },
  });
  return { token: session.access_token, publicID: profile.public_id, username };
}

/// Minimaler Realtime-Client (Protokoll 1.0.0): ein Socket je Nutzer, Kanäle mit Zugriffstoken.
class RealtimeConnection {
  constructor(token) {
    this.token = token;
    this.ref = 0;
    this.pending = new Map();
    this.broadcasts = [];
    this.listeners = [];
  }

  async open() {
    const url = new URL("/realtime/v1/websocket", baseURL);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.searchParams.set("apikey", apiKey);
    url.searchParams.set("vsn", "1.0.0");
    this.socket = new WebSocket(url);
    this.socket.addEventListener("message", (event) => this.receive(JSON.parse(event.data)));
    await new Promise((resolve, reject) => {
      this.socket.addEventListener("open", resolve, { once: true });
      this.socket.addEventListener("error", () => reject(new Error("WebSocket-Fehler")), { once: true });
    });
  }

  receive(message) {
    if (message.event === "phx_reply" && this.pending.has(message.ref)) {
      this.pending.get(message.ref)(message.payload);
      this.pending.delete(message.ref);
    } else if (message.event === "broadcast") {
      this.broadcasts.push({ topic: message.topic, ...message.payload });
      this.listeners.forEach((listener) => listener());
    } else if (message.event === "system" && message.payload?.status === "error") {
      // Abgelehnter Beitritt kann zusätzlich als Systemnachricht kommen.
      this.broadcasts.push({ topic: message.topic, system: message.payload });
    }
  }

  push(topic, event, payload) {
    const ref = String(++this.ref);
    this.socket.send(JSON.stringify({ topic, event, payload, ref, join_ref: ref }));
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve({ status: "timeout" }), TIMEOUT_MS);
      this.pending.set(ref, (reply) => {
        clearTimeout(timer);
        resolve(reply);
      });
    });
  }

  /// `true`, wenn der Server den Beitritt zum privaten Kanal bestätigt.
  async join(topic) {
    const reply = await this.push(`realtime:${topic}`, "phx_join", {
      config: { broadcast: { ack: false, self: false }, presence: { key: "" }, postgres_changes: [], private: true },
      access_token: this.token,
    });
    return reply.status === "ok";
  }

  waitForBroadcast(topic, event) {
    const find = () => this.broadcasts.find((b) => b.topic === `realtime:${topic}` && b.event === event);
    return new Promise((resolve) => {
      const found = find();
      if (found) return resolve(found);
      const timer = setTimeout(() => resolve(null), TIMEOUT_MS);
      this.listeners.push(() => {
        const match = find();
        if (match) {
          clearTimeout(timer);
          resolve(match);
        }
      });
    });
  }

  close() {
    this.socket?.close();
  }
}

const anna = await newUser("rt_anna");
const ben = await newUser("rt_ben");
const outsider = await newUser("rt_fremd");

await rpc(anna.token, "social_send_friend_request", { p_public_id: ben.publicID });
const requests = await rpc(ben.token, "social_friend_requests");
const incoming = requests.find((r) => r.direction === "incoming");
await rpc(ben.token, "social_respond_friend_request", { p_request_id: incoming.request_id, p_accept: true });
const conversation = await rpc(anna.token, "chat_open_direct", { p_public_id: ben.publicID });

const chatTopic = `chat:${conversation.id}`;
const benTopic = `user:${ben.publicID}`;

const benSocket = new RealtimeConnection(ben.token);
const outsiderSocket = new RealtimeConnection(outsider.token);
await benSocket.open();
await outsiderSocket.open();

try {
  check(await benSocket.join(chatTopic), "Teilnehmer abonniert chat:<conversation_id>");
  check(await benSocket.join(benTopic), "Teilnehmer abonniert user:<eigene public_id>");
  check(!(await outsiderSocket.join(chatTopic)), "Fremde werden bei chat:<conversation_id> abgewiesen");
  check(!(await outsiderSocket.join(benTopic)), "Fremde werden bei user:<public_id> anderer abgewiesen");

  const secret = `Geheim ${crypto.randomUUID()}`;
  const sent = await rpc(anna.token, "chat_send", {
    p_conversation_id: conversation.id,
    p_client_id: crypto.randomUUID(),
    p_kind: "text",
    p_body: secret,
    p_media_path: null,
    p_shared_profile_id: null,
  });

  const messageHint = await benSocket.waitForBroadcast(chatTopic, "message");
  const listHint = await benSocket.waitForBroadcast(benTopic, "conversation");
  check(messageHint !== null, "Hinweis „message“ auf chat:<conversation_id> angekommen");
  check(listHint !== null, "Hinweis „conversation“ auf user:<public_id> angekommen");
  check(messageHint?.payload?.conversation_id === conversation.id, "Hinweis nennt die Unterhaltung");
  check(!JSON.stringify(messageHint ?? {}).includes(secret) && !JSON.stringify(listHint ?? {}).includes(secret),
    "Hinweise enthalten keinen Nachrichteninhalt");
  check(!outsiderSocket.broadcasts.some((b) => b.event === "message" || b.event === "conversation"),
    "Fremde empfangen keine Hinweise");

  const edited = `Bearbeitet ${crypto.randomUUID()}`;
  await rpc(anna.token, "chat_edit_message", { p_message_id: sent.id, p_text: edited });
  const updateHint = await benSocket.waitForBroadcast(chatTopic, "message_updated");
  check(updateHint !== null, "Hinweis „message_updated“ nach dem Bearbeiten angekommen");
  check(!JSON.stringify(updateHint ?? {}).includes(edited), "Bearbeitungs-Hinweis ohne Nachrichteninhalt");

  await rpc(ben.token, "chat_set_pinned", { p_message_id: sent.id, p_pinned: true });
  const pinHint = await benSocket.waitForBroadcast(chatTopic, "pins_changed");
  check(pinHint !== null, "Hinweis „pins_changed“ nach dem Anpinnen angekommen");
  check(pinHint?.payload?.conversation_id === conversation.id, "Pin-Hinweis nennt die Unterhaltung");
  check(!outsiderSocket.broadcasts.some((b) => b.event === "message_updated" || b.event === "pins_changed"),
    "Fremde empfangen keine Bearbeitungs- oder Pin-Hinweise");
} finally {
  benSocket.close();
  outsiderSocket.close();
}

if (failures > 0) {
  console.error(`${failures} Prüfung(en) fehlgeschlagen.`);
  process.exit(1);
}
console.log("Realtime: alle Prüfungen bestanden.");
