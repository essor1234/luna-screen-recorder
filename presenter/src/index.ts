import { DurableObject } from "cloudflare:workers";
import { NOTES } from "./notes";

export interface Env {
  RELAY: DurableObjectNamespace<Relay>;
  REMOTE_KEY: string;
}

type Role = "deck" | "remote";

// Close codes the pages act on. 4001 means the link's key is wrong, so they stop retrying.
export const BAD_KEY = 4001;
export const BAD_REQUEST = 4400;

const MAX_MESSAGE = 8192;

async function keyMatches(given: string | null, expected: string | undefined): Promise<boolean> {
  if (!given || !expected) return false;
  // Hash both sides first so the comparison is constant time whatever the lengths.
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

// A browser can't read the HTTP status of a failed WebSocket upgrade, so accept the socket
// and close it straight away with a code the page can read.
function refuse(code: number, reason: string): Response {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.close(code, reason);
  return new Response(null, { status: 101, webSocket: client });
}

export default {
  async fetch(req, env): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname === "/") {
      return new Response("Luna presenter relay. Open your remote link instead.\n", {
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }
    if (url.pathname !== "/ws") return new Response("Not found", { status: 404 });
    if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("This address only takes WebSocket connections.", { status: 426 });
    }
    const role = url.searchParams.get("role");
    if (role !== "deck" && role !== "remote") return refuse(BAD_REQUEST, "role must be deck or remote");
    if (!(await keyMatches(url.searchParams.get("key"), env.REMOTE_KEY))) return refuse(BAD_KEY, "wrong key");
    return env.RELAY.get(env.RELAY.idFromName("main")).fetch(req);
  },
} satisfies ExportedHandler<Env>;

function send(ws: WebSocket, msg: unknown): void {
  try {
    ws.send(JSON.stringify(msg));
  } catch {
    // Socket already closing; presence catches up on its close event.
  }
}

// Remotes send {type:"cmd"} to the decks. Decks send {type:"state"} to the remotes.
// Nothing is stored: when a remote joins, the deck is asked to resend its state.
export class Relay extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // Keepalive pings get answered without waking the object.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  override async fetch(req: Request): Promise<Response> {
    const role = new URL(req.url).searchParams.get("role") as Role;
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, [role]);
    if (role === "remote") {
      send(server, { type: "hello", notes: NOTES, deck: this.sockets("deck").length > 0 });
      this.broadcast("deck", { type: "sync" });
    } else {
      send(server, { type: "hello" });
    }
    this.presence();
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    if (typeof raw !== "string" || raw.length > MAX_MESSAGE) return;
    let msg: { type?: unknown };
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const role = this.ctx.getTags(ws)[0] as Role | undefined;
    if (role === "remote" && msg.type === "cmd") this.broadcast("deck", msg);
    else if (role === "deck" && msg.type === "state") this.broadcast("remote", msg);
  }

  override async webSocketClose(ws: WebSocket): Promise<void> {
    try {
      ws.close(1000, "bye");
    } catch {
      // Already closed.
    }
    this.presence(ws);
  }

  override async webSocketError(ws: WebSocket): Promise<void> {
    this.presence(ws);
  }

  private sockets(role: Role, leaving?: WebSocket): WebSocket[] {
    return this.ctx.getWebSockets(role).filter((s) => s !== leaving);
  }

  private broadcast(role: Role, msg: unknown, leaving?: WebSocket): void {
    for (const s of this.sockets(role, leaving)) send(s, msg);
  }

  private presence(leaving?: WebSocket): void {
    const decks = this.sockets("deck", leaving).length;
    const remotes = this.sockets("remote", leaving).length;
    this.broadcast("remote", { type: "presence", deck: decks > 0 }, leaving);
    this.broadcast("deck", { type: "presence", remotes }, leaving);
  }
}
