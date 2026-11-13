#!/usr/bin/env python3
"""Checks, from a Mac, whether a ChatGPT account can do what the app's Describe a workout needs.

It signs in with OpenAI's "Sign in with ChatGPT" flow for open-source apps, prints the granted scope
and the models the plan lists, asks for one routine with a JSON Schema, and revokes its sign-in.
It stores nothing. It leaves an app named "Intervals probe" in the ChatGPT account, which can be
removed there. It does not verify the ID token, so it is a probe and not app code.

It last ran against OpenAI on 2026-11-12 and every step answered. No test runs it, and CI must not.
Run it with a Python whose certificate store works, such as /usr/bin/python3.

Usage: chatgpt-probe.py            (optionally MODEL=gpt-6.1-sol chatgpt-probe.py)
"""
import base64, hashlib, http.server, json, os, secrets, socketserver, urllib.parse, urllib.request, uuid, webbrowser
AUTH = "https://auth.openai.com/api/accounts/authorize"
TOKEN = "https://auth.openai.com/api/accounts/oauth/token"
RES = "https://api.openai.com/v1"
MODEL = os.environ.get("MODEL", "gpt-6-luna")
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
verifier, state, nonce = b64(secrets.token_bytes(32)), b64(secrets.token_bytes(32)), b64(secrets.token_bytes(32))
got = {}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = dict(urllib.parse.parse_qsl(u.query))
        ok = u.path == "/auth/callback" and q.get("state") == state
        self.send_response(200 if ok else 404); self.end_headers()
        self.wfile.write(b"Done. Return to the terminal." if ok else b"Not found")
        if ok: got.update(q)
    def log_message(self, *a): pass
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
redirect = f"http://127.0.0.1:{srv.server_address[1]}/auth/callback"
params = dict(client_id="dynamic_agent_client", agent_name_hint="Intervals probe",
    ext_agent_host_id=f"urn:uuid:{uuid.uuid4()}", response_type="code", redirect_uri=redirect,
    scope="openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
    resource=RES, state=state, nonce=nonce, code_challenge_method="S256",
    code_challenge=b64(hashlib.sha256(verifier.encode()).digest()))
url = AUTH + "?" + urllib.parse.urlencode(params)
print("Open:", url); webbrowser.open(url)
while not got: srv.handle_request()
if "error" in got: raise SystemExit(f"authorization failed: {got['error']}")
def post(u, data, headers):
    req = urllib.request.Request(u, data=data, headers=headers)
    try: return urllib.request.urlopen(req)
    except urllib.error.HTTPError as e: raise SystemExit(f"{u} -> HTTP {e.code}: {e.read().decode()[:600]}")
tok = json.load(post(TOKEN, urllib.parse.urlencode(dict(grant_type="authorization_code",
    client_id=got["client_id"], code=got["code"], code_verifier=verifier, redirect_uri=redirect,
    resource=RES)).encode(), {"Content-Type": "application/x-www-form-urlencoded"}))
print("issued client_id prefix:", got["client_id"][:7], "| scope:", tok.get("scope"), "| expires_in:", tok.get("expires_in"))
auth = {"Authorization": "Bearer " + tok["access_token"]}
models = json.load(urllib.request.urlopen(urllib.request.Request(RES + "/models", headers=auth)))
print("models:", [m.get("slug") for m in models.get("models", []) if m.get("visibility") == "list"])
schema = {"type": "object", "additionalProperties": False, "required": ["title", "steps"], "properties": {
    "title": {"type": "string"}, "steps": {"type": "array", "items": {"type": "object",
    "additionalProperties": False, "required": ["name", "seconds"],
    "properties": {"name": {"type": "string"}, "seconds": {"type": "integer"}}}}}}
body = {"model": MODEL, "store": False, "stream": True,
    "instructions": "Return a stretch routine as JSON.",
    "input": [{"role": "user", "content": "15-minute hip mobility routine"}],
    "text": {"format": {"type": "json_schema", "name": "routine", "strict": True, "schema": schema}}}
out, done = "", False
for raw in post(RES + "/responses", json.dumps(body).encode(), {**auth, "Content-Type": "application/json", "Accept": "text/event-stream"}):
    line = raw.decode().strip()
    if not line.startswith("data:"): continue
    ev = json.loads(line[5:])
    if ev.get("type") == "response.output_text.delta": out += ev["delta"]
    elif ev.get("type") in ("response.failed", "error"): raise SystemExit(f"failed: {json.dumps(ev)[:600]}")
    elif ev.get("type") == "response.completed": done = True
print("completed:", done); print(json.dumps(json.loads(out), indent=2))
try: post("https://auth.openai.com/api/accounts/oauth/revoke", urllib.parse.urlencode(dict(token=tok["refresh_token"],
    token_type_hint="refresh_token", client_id=got["client_id"])).encode(), {"Content-Type": "application/x-www-form-urlencoded"}); print("session revoked")
except BaseException as e: print("revoke not confirmed:", e)
