// End-to-end check against the deployed relay. Node 22+ (global WebSocket).
//   node test/e2e.mjs
// Key: $LUNA_REMOTE_KEY, else ~/.config/luna/presenter-key.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";

const BASE = process.env.LUNA_REMOTE_URL ?? "wss://luna-remote.nimitbhargava.workers.dev/ws";
const KEY = process.env.LUNA_REMOTE_KEY ?? readFileSync(`${homedir()}/.config/luna/presenter-key`, "utf8").trim();

let failed = 0;
function check(name, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? `  (${detail})` : ""}`);
  if (!ok) failed++;
}

function open(role, key = KEY) {
  const ws = new WebSocket(`${BASE}?role=${role}&key=${encodeURIComponent(key)}`);
  const inbox = [];
  const waiters = [];
  ws.addEventListener("message", (e) => {
    const msg = JSON.parse(e.data);
    const i = waiters.findIndex((w) => w.match(msg));
    if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
    else inbox.push(msg);
  });
  const closed = new Promise((r) => ws.addEventListener("close", (e) => r(e.code)));
  const opened = new Promise((r, j) => {
    ws.addEventListener("open", r);
    ws.addEventListener("error", j);
  });
  function next(match, ms = 5000) {
    const i = inbox.findIndex(match);
    if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const w = { match, resolve };
      waiters.push(w);
      setTimeout(() => {
        const at = waiters.indexOf(w);
        if (at >= 0) { waiters.splice(at, 1); reject(new Error("timed out")); }
      }, ms);
    });
  }
  const send = (m) => ws.send(JSON.stringify(m));
  return { ws, next, send, closed, opened };
}

const withTimeout = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(() => r("timeout"), ms))]);

// 1. Wrong key and wrong role are refused with codes the pages can read.
check("wrong key closes with 4001", (await withTimeout(open("remote", "not-the-key").closed, 8000)) === 4001);
check("missing role closes with 4400", (await withTimeout(open("viewer").closed, 8000)) === 4400);

// 2. A deck and a remote talk through the relay.
const deck = open("deck");
await deck.opened;
await deck.next((m) => m.type === "hello");
const remote = open("remote");
await remote.opened;
const hello = await remote.next((m) => m.type === "hello");
check("remote gets notes on hello", Array.isArray(hello.notes?.["Luna"]), `${Object.keys(hello.notes ?? {}).length} slides`);
check("remote sees the deck online", hello.deck === true);
check("deck is asked to resend its state", !!(await deck.next((m) => m.type === "sync").catch(() => null)));
const presence = await deck.next((m) => m.type === "presence" && m.remotes > 0).catch(() => null);
check("deck sees the remote join", !!presence, presence ? `${presence.remotes} remote(s)` : "");

deck.send({ type: "state", index: 3, total: 11, titles: ["Luna"] });
const state = await remote.next((m) => m.type === "state").catch(() => null);
check("deck state reaches the remote", state?.index === 3);

remote.send({ type: "cmd", action: "next" });
const cmd = await deck.next((m) => m.type === "cmd").catch(() => null);
check("remote command reaches the deck", cmd?.action === "next");

// 3. A remote can't pretend to be the deck.
const other = open("remote");
await other.opened;
await other.next((m) => m.type === "hello");
remote.send({ type: "state", index: 9 });
const spoofed = await other.next((m) => m.type === "state", 1500).catch(() => null);
check("remote can't send deck state", spoofed === null);

// 4. Presence when the deck leaves.
deck.ws.close();
const gone = await remote.next((m) => m.type === "presence" && m.deck === false).catch(() => null);
check("remote sees the deck go offline", !!gone);

remote.ws.close();
other.ws.close();
console.log(failed ? `\n${failed} failed` : "\nAll passed");
process.exit(failed ? 1 : 0);
