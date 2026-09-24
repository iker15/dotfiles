#!/usr/bin/env python3
# Vecindario de Mochi: mandar TU Mochi de visita a la pantalla de otra persona (con Mochi
# instalado) y recibir el suyo. Va por ntfy.sh (servicio de mensajes gratuito, sin cuentas) en un
# canal secreto por pareja de vecinos; cada mensaje va firmado (HMAC) con una clave que solo
# tenéis vosotros dos, así que nadie más puede mandar ni hacerse pasar por un Mochi.
#
# Lo lanza Mochi (shell.qml) y hablan por líneas JSON:
#   Mochi → aquí (stdin):  {"cmd": "invite", "me": "Iker", "side": "right"}
#                          {"cmd": "join", "me": "Iker", "code": "mochi:…"}
#                          {"cmd": "send", "to": "Pablo", "type": "visit|return|recall", "mochi": {…}}
#                          {"cmd": "remove", "name": "Pablo"}
#   aquí → Mochi (stdout): {"ev": "neighbours", "list": [{"name", "side", "online"}]}
#                          {"ev": "invite", "code": "mochi:…"}
#                          {"ev": "visit"|"return"|"recall", "from": "Pablo", "side": "right", "mochi": {…}}
#                          {"ev": "error", "text": …}
# Datos (con las claves: NO van a los dotfiles): ~/.local/state/tamagotchi/vecinos.json
import base64, hashlib, hmac, json, os, secrets, sys, threading, time, urllib.request

SERVER = "https://ntfy.sh"
STATE = os.environ.get("MOCHI_VECINOS", os.path.expanduser("~/.local/state/tamagotchi/vecinos.json"))
lock = threading.Lock()
cfg = {"id": secrets.token_hex(6), "neighbours": []}
last_seen = {}    # nombre → última vez que dio señales (s)
started = set()   # canales a los que ya se escucha


def out(**ev):
    with lock:
        print(json.dumps(ev, ensure_ascii=False), flush=True)


def save():
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, STATE)


def load():
    global cfg
    try:
        cfg = json.load(open(STATE))
    except Exception:
        save()
    cfg.setdefault("id", secrets.token_hex(6))
    cfg.setdefault("neighbours", [])


def sign(secret, body):
    return hmac.new(secret.encode(), body.encode(), hashlib.sha256).hexdigest()


def publish(n, kind, data=None):
    msg = {"v": 1, "from": cfg["id"], "name": cfg.get("me", "?"), "type": kind, "ts": int(time.time()), "data": data or {}}
    body = json.dumps(msg, sort_keys=True, separators=(",", ":"))
    payload = json.dumps({"m": body, "sig": sign(n["secret"], body)})
    req = urllib.request.Request(f"{SERVER}/{n['topic']}", data=payload.encode(), method="POST")
    try:
        urllib.request.urlopen(req, timeout=15).read()
        return True
    except Exception as e:
        out(ev="error", text=f"no se pudo mandar a {n['name']}: {e}")
        return False


def neighbours_event():
    now = time.time()
    out(ev="neighbours", me=cfg.get("me", ""), list=[{"name": n["name"], "side": n["side"], "online": now - last_seen.get(n["name"], 0) < 420} for n in cfg["neighbours"]])


def listen(n):
    """Escucha el canal de un vecino (recoge también lo que llegó mientras estabas apagado)."""
    topic = n["topic"]
    while any(x["topic"] == topic for x in cfg["neighbours"]):
        since = n.get("since", "12h")
        try:
            with urllib.request.urlopen(f"{SERVER}/{topic}/json?since={since}", timeout=90) as r:
                for raw in r:
                    try:
                        m = json.loads(raw)
                    except ValueError:
                        continue
                    if m.get("event") != "message":
                        continue
                    n["since"] = m["id"]
                    handle(n, m.get("message", ""))
        except Exception:
            time.sleep(10)


def handle(n, text):
    try:
        wrap = json.loads(text)
        body, sig = wrap["m"], wrap["sig"]
    except Exception:
        return
    if not hmac.compare_digest(sign(n["secret"], body), sig):
        return   # no es de tu vecino
    msg = json.loads(body)
    if msg.get("from") == cfg["id"]:
        return   # lo he mandado yo
    if n.get("pending"):
        # el invitado se ha unido: su mensaje trae su nombre
        n["name"] = msg.get("name") or "vecino"
        n.pop("pending", None)
    save()   # (guarda por dónde va el canal)
    last_seen[n["name"]] = time.time()
    kind = msg.get("type")
    if kind in ("ping", "hello"):
        if kind == "hello":
            publish(n, "ping")   # (que él también sepa ya que estoy)
        neighbours_event()
    elif kind in ("visit", "return", "recall"):
        # (una visita de hace mucho ya no cuenta: el otro Mochi habrá vuelto a casa)
        if kind == "visit" and time.time() - msg.get("ts", 0) > 6 * 3600:
            return
        out(ev=kind, **{"from": n["name"]}, side=n["side"], mochi=msg.get("data", {}).get("mochi", {}))
        neighbours_event()


def start_listening():
    for n in cfg["neighbours"]:
        if n["topic"] not in started:
            started.add(n["topic"])
            threading.Thread(target=listen, args=(n,), daemon=True).start()


def pinger():
    while True:
        for n in list(cfg["neighbours"]):
            publish(n, "ping")
        neighbours_event()
        time.sleep(180)


def command(c):
    kind = c.get("cmd")
    if c.get("me"):
        cfg["me"] = c["me"]
    if kind == "invite":
        # un canal y una clave nuevos; el código lleva también de qué lado estará para él
        side = c.get("side", "right")
        code = {"t": "mochi-" + secrets.token_urlsafe(18), "k": secrets.token_urlsafe(24), "n": cfg.get("me", "?"), "s": "left" if side == "right" else "right"}
        # escuchar ya el canal: cuando se una, su primer saludo dirá cómo se llama
        pend = {"name": "(pendiente)", "topic": code["t"], "secret": code["k"], "side": side, "pending": True}
        cfg["neighbours"].append(pend)
        save()
        start_listening()
        out(ev="invite", code="mochi:" + base64.urlsafe_b64encode(json.dumps(code).encode()).decode().rstrip("="))
    elif kind == "join":
        try:
            raw = c["code"].strip().removeprefix("mochi:")
            code = json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
        except Exception:
            out(ev="error", text="ese código no es válido")
            return
        cfg["neighbours"] = [x for x in cfg["neighbours"] if x["topic"] != code["t"]]
        n = {"name": code["n"], "topic": code["t"], "secret": code["k"], "side": code["s"]}
        cfg["neighbours"].append(n)
        save()
        start_listening()
        publish(n, "hello")
        neighbours_event()
    elif kind == "send":
        n = next((x for x in cfg["neighbours"] if x["name"] == c.get("to")), None)
        if not n:
            out(ev="error", text=f"no tienes ningún vecino llamado {c.get('to')}")
            return
        ok = publish(n, c.get("type", "visit"), {"mochi": c.get("mochi", {})})
        out(ev="sent", to=n["name"], type=c.get("type"), ok=ok)
    elif kind == "remove":
        cfg["neighbours"] = [x for x in cfg["neighbours"] if x["name"] != c.get("name")]
        save()
        neighbours_event()


def main():
    load()
    start_listening()
    threading.Thread(target=pinger, daemon=True).start()
    neighbours_event()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            command(json.loads(line))
        except Exception as e:
            out(ev="error", text=str(e))


if __name__ == "__main__":
    main()
