"""Helpers for phase 45 (web search). Standard library only; never prints a key.

  render  TEMPLATE OUT            install settings.yml (mode 600)
  wait    URL SECONDS             wait until SearXNG answers a JSON search with results
  engines URL                     per-engine table for three test queries; exit 2 = WARN
  mcp     URL                     MCP handshake: initialize, notifications/initialized, tools/list
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

GENERAL = ["bing", "duckduckgo", "mojeek", "startpage", "qwant", "yahoo", "brave", "google", "google cse", "wikipedia"]
QUERIES = [("linux kernel scheduler", "general"), ("python asyncio gather example", "general,it"),
           ("tokio async runtime", "general,it,packages,science")]


def render(template, out):
    """Install settings.yml with mode 600 (it is read with the secret key in the environment)."""
    text = open(template).read()
    old = os.umask(0o077)
    try:
        with open(out + ".tmp", "w") as f:
            f.write(text)
        os.replace(out + ".tmp", out)
    finally:
        os.umask(old)
    os.chmod(out, 0o600)


def search(url, q, categories="general"):
    u = f"{url}/search?" + urllib.parse.urlencode({"q": q, "format": "json", "categories": categories})
    with urllib.request.urlopen(u, timeout=30) as r:
        return json.load(r)


def wait(url, seconds):
    end = time.time() + float(seconds)
    last = "no answer"
    while time.time() < end:
        try:
            d = search(url, "test")
            if d.get("results"):
                print(f"OK   search: {len(d['results'])} results for 'test'")
                return 0
            last = f"0 results; unresponsive: {d.get('unresponsive_engines')}"
        except Exception as e:  # noqa: BLE001 - report any failure, then retry
            last = str(e)
        time.sleep(3)
    print(f"FAIL search: {last}")
    return 1


def engines(url):
    answered, refused, counts = {}, {}, {}
    for q, cat in QUERIES:
        d = search(url, q, cat)
        counts[q] = len(d.get("results", []))
        for res in d.get("results", []):
            for e in res.get("engines", []):
                answered.setdefault(e, set()).add(q)
        for e, why in d.get("unresponsive_engines", []):
            refused.setdefault(e, why)
    print(f"     {'engine':<16} {'answered':<9} note")
    for e in sorted(set(answered) | set(refused)):
        n = len(answered.get(e, ()))
        print(f"     {e:<16} {n}/{len(QUERIES):<7} {refused.get(e, '') if n == 0 else ''}")
    print("     results per query: " + ", ".join(f"{q!r}={n}" for q, n in counts.items()))
    general = sorted(e for e in answered if e in GENERAL)
    print(f"OK   general engines that answered: {', '.join(general) or 'none'}")
    if len(general) < 3:
        print(f"WARN only {len(general)} general engine(s) answer from this address. Search works, with less "
              "coverage.\n     SearXNG suspends a refusing engine and tries it again later: run "
              "'phases/45-search.sh test' later to see the table again.")
        return 2
    return 0


def rpc(url, body, session=None):
    hdr = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if session:
        hdr["Mcp-Session-Id"] = session
    req = urllib.request.Request(url, json.dumps(body).encode(), hdr)
    with urllib.request.urlopen(req, timeout=30) as r:
        sid = r.headers.get("Mcp-Session-Id")
        raw = r.read().decode()
    if not raw.strip():
        return sid, None
    if raw.lstrip().startswith("{"):
        return sid, json.loads(raw)
    data = [ln[5:].strip() for ln in raw.splitlines() if ln.startswith("data:")]
    return sid, json.loads(data[-1]) if data else None


def mcp(url):
    sid, init = rpc(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "pilot-kit", "version": "1"}}})
    if not sid:
        print("FAIL mcp: no Mcp-Session-Id after initialize")
        return 1
    rpc(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    _, tl = rpc(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, sid)
    tools = sorted(t["name"] for t in (tl or {}).get("result", {}).get("tools", []))
    server = (init or {}).get("result", {}).get("serverInfo", {})
    want = {"searxng_web_search", "searxng_search_suggestions", "searxng_instance_info", "web_url_read"}
    ok = want <= set(tools)
    print(("OK   " if ok else "FAIL ") + f"mcp {server.get('name', '?')} {server.get('version', '')}: "
          f"{len(tools)} tools {tools}")
    return 0 if ok else 1


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "render":
        render(*args)
    elif cmd == "wait":
        sys.exit(wait(*args))
    elif cmd == "engines":
        sys.exit(engines(*args))
    elif cmd == "mcp":
        sys.exit(mcp(*args))
    else:
        sys.exit(__doc__)
