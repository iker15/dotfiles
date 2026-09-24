#!/usr/bin/env python3
# Vecindario de Mochi: mandar TU Mochi de visita a la pantalla de otra persona (con Mochi
# instalado) y recibir el suyo. Va por ntfy.sh (servicio de mensajes gratuito, sin cuentas) en un
# canal secreto por pareja de vecinos; cada mensaje va firmado (HMAC) con una clave que solo
# tenéis vosotros dos, así que nadie más puede mandar ni hacerse pasar por un Mochi.
#
# Lo lanza Mochi (shell.qml) y hablan por líneas JSON:
#   Mochi → aquí (stdin):  {"cmd": "invite", "me": "Iker", "side": "right"}
#                          {"cmd": "join", "me": "Iker", "code": "mochi:…"}
#                          {"cmd": "send", "to": "Pablo", "type": "visit|return|recall", "mochi": {…}, "vid": "…"}
#                          {"cmd": "remove"|"block"|"unblock", "name": "Pablo"}
#                          {"cmd": "door", "open": true|false}     (cerrada: no se aceptan visitas)
#   aquí → Mochi (stdout): {"ev": "neighbours", "me", "closed", "list": [{"name", "side", "online", "blocked", "pending"}]}
#                          {"ev": "invite", "code": "mochi:…"}
#                          {"ev": "visit"|"return"|"recall", "from": "Pablo", "side": "right", "mochi": {…}, "vid", "refused"}
#                          {"ev": "knock", "from": "Pablo"}   (vino con la puerta cerrada: ha vuelto a su casa)
#                          {"ev": "gone", "name": "Pablo"}    (te ha quitado de sus vecinos)
#                          {"ev": "error", "text": …}
# Cada visita lleva un id (vid): la vuelta y el «vuelve a casa» lo repiten, así un mensaje viejo
# (de otra visita) no trae ni echa a nadie por error.
# Si alguien está bloqueado, sus visitas se le devuelven al momento («la puerta está cerrada»,
# sin decirle que es un bloqueo) y tu Mochi no puede ir a su casa.
# Datos (con las claves: NO van a los dotfiles): ~/.local/state/tamagotchi/vecinos.json
import base64, hashlib, hmac, json, os, secrets, sys, threading, time, urllib.request

SERVER = "https://ntfy.sh"
STATE = os.environ.get("MOCHI_VECINOS", os.path.expanduser("~/.local/state/tamagotchi/vecinos.json"))
VISIT_MAX = 6 * 3600   # una visita más vieja ya no cuenta (se le devuelve)
ONLINE = 420           # da señales cada 3 min: conectado si hace menos de 7
lock = threading.RLock()
cfg = {"id": secrets.token_hex(6), "neighbours": [], "closed": False}
last_seen = {}    # canal → última vez que dio señales (s, hora del mensaje)
started = set()   # canales a los que ya se escucha


def out(**ev):
    with lock:
        print(json.dumps(ev, ensure_ascii=False), flush=True)


def save():
    with lock:
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
    cfg.setdefault("closed", False)


def find(topic):
    return next((x for x in cfg["neighbours"] if x["topic"] == topic), None)


def by_name(name):
    return next((x for x in cfg["neighbours"] if x["name"] == name and not x.get("pending")), None)


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
    out(ev="neighbours", me=cfg.get("me", ""), closed=cfg.get("closed", False), list=[{
        "name": n["name"], "side": n["side"],
        "online": not n.get("blocked") and now - last_seen.get(n["topic"], 0) < ONLINE,
        "blocked": bool(n.get("blocked")), "pending": bool(n.get("pending")),
    } for n in cfg["neighbours"]])


def unique_name(name, topic):
    base, i = name or "vecino", 2
    name = base
    while any(x["name"] == name and x["topic"] != topic for x in cfg["neighbours"]):
        name, i = f"{base} {i}", i + 1
    return name


def verify(n, text):
    """El mensaje, si es de verdad de tu vecino (firmado con vuestra clave) y no tuyo."""
    try:
        wrap = json.loads(text)
        body, sig = wrap["m"], wrap["sig"]
        if not hmac.compare_digest(sign(n["secret"], body), sig):
            return None
        msg = json.loads(body)
    except Exception:
        return None
    if msg.get("from") == cfg["id"]:
        return None   # lo he mandado yo
    if n.get("pending"):
        # el invitado se ha unido: su mensaje trae su nombre
        n["name"] = unique_name(msg.get("name"), n["topic"])
        n.pop("pending", None)
    last_seen[n["topic"]] = max(last_seen.get(n["topic"], 0), min(time.time(), msg.get("ts", 0)))
    return msg


def mochi_of(msg):
    return msg.get("data", {}).get("mochi", {}) or {}


def refuse(n, msg, reason):
    """Le devuelve su Mochi al momento (sin entrar)."""
    m = mochi_of(msg)
    publish(n, "return", {"mochi": m, "vid": msg.get("data", {}).get("vid") or m.get("vid"), "refused": reason})
    if reason == "closed" and not n.get("blocked"):
        out(ev="knock", **{"from": n["name"]})


def deliver(n, msg):
    """Lo que ha llegado (en directo o del atasco al arrancar) → a Mochi."""
    kind, data = msg.get("type"), msg.get("data", {})
    if kind == "hello":
        publish(n, "ping")   # (que él también sepa ya que estoy)
    elif kind == "bye":
        cfg["neighbours"] = [x for x in cfg["neighbours"] if x["topic"] != n["topic"]]
        save()
        out(ev="gone", name=n["name"])
    elif kind == "visit":
        if n.get("blocked") or cfg.get("closed"):
            refuse(n, msg, "closed")
        elif time.time() - msg.get("ts", 0) > VISIT_MAX:
            refuse(n, msg, "late")
        else:
            out(ev="visit", **{"from": n["name"]}, side=n["side"], mochi=mochi_of(msg), vid=data.get("vid") or mochi_of(msg).get("vid"))
    elif kind in ("return", "recall"):
        if not n.get("blocked") or kind == "return":   # (a tu Mochi te lo devuelven siempre)
            out(ev=kind, **{"from": n["name"]}, side=n["side"], mochi=mochi_of(msg), vid=data.get("vid") or mochi_of(msg).get("vid"), refused=data.get("refused", ""))
    neighbours_event()


def backlog(n, msgs):
    """Lo que llegó mientras estabas apagado, resumido: una visita que ya se llamaron de vuelta
    no aparece un segundo para irse; de las vueltas de tu Mochi solo cuenta la última."""
    visit, ret, rest = None, None, []
    for m in msgs:
        kind = m.get("type")
        if kind == "visit":
            if visit:
                refuse(n, visit, "late")
            visit = m
        elif kind == "recall":
            vid = m.get("data", {}).get("vid")
            if visit and (not vid or vid == visit.get("data", {}).get("vid")):
                visit = None   # vino y se lo llevaron antes de que lo vieras
            else:
                rest.append(m)   # (quizá era un visitante de antes, que sigue aquí)
        elif kind == "return":
            ret = m
        elif kind in ("hello", "bye"):
            rest.append(m)
    for m in rest + [x for x in (ret, visit) if x]:
        if find(n["topic"]):
            deliver(n, m)
    neighbours_event()


def fetch(topic, since):
    """Los mensajes guardados en el canal desde `since` (sin quedarse escuchando)."""
    out_ = []
    with urllib.request.urlopen(f"{SERVER}/{topic}/json?poll=1&since={since}", timeout=30) as r:
        for raw in r:
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            if m.get("event") == "message":
                out_.append(m)
    return out_


def fresh(topic, m):
    """¿No lo habíamos visto ya? (entre la recogida y la escucha pueden llegar repetidos; se
    guarda con el vecino, así tampoco se repite nada al reiniciar)"""
    n = find(topic)
    s = n.setdefault("seen", []) if n else []
    if m["id"] in s:
        return False
    s.append(m["id"])
    del s[:-80]
    return True


def take(topic, m):
    """Un mensaje del canal → verificado y entregado (si es nuevo y el vecino sigue ahí)."""
    n = find(topic)
    if not n or not fresh(topic, m):
        return
    n["since"] = m["id"]
    msg = verify(n, m.get("message", ""))
    save()   # (guarda por dónde va el canal)
    if msg:
        deliver(n, msg)


def recheck(topic, since):
    """ntfy tarda un poco en guardar lo que llega: lo publicado justo mientras te suscribías
    no sale ni en la recogida ni en directo. Se vuelve a mirar al poco, sin repetir nada."""
    for wait in (4, 11):   # (a veces tarda varios segundos)
        time.sleep(wait)
        try:
            for m in fetch(topic, since):
                take(topic, m)
        except Exception:
            pass


def listen(topic):
    """Escucha el canal de un vecino: primero lo atrasado (resumido), luego en directo."""
    caught_up = False
    while True:
        n = find(topic)
        if not n:
            started.discard(topic)
            return
        try:
            if not caught_up:
                t0 = int(time.time()) - 15
                msgs = []
                for m in fetch(topic, n.get("since", "12h")):
                    if not fresh(topic, m):
                        continue
                    n["since"] = m["id"]
                    msg = verify(n, m.get("message", ""))
                    if msg:
                        msgs.append(msg)
                save()
                backlog(n, msgs)
                caught_up = True
            else:
                t0 = int(time.time()) - 15
            # (desde un poco antes: lo repetido se descarta por su id)
            with urllib.request.urlopen(f"{SERVER}/{topic}/json?since={t0}", timeout=90) as r:
                for raw in r:
                    try:
                        m = json.loads(raw)
                    except ValueError:
                        continue
                    if not find(topic):
                        break   # lo has quitado: se deja de escuchar
                    if m.get("event") == "open":
                        threading.Thread(target=recheck, args=(topic, t0), daemon=True).start()
                    elif m.get("event") == "message":
                        take(topic, m)
        except Exception:
            time.sleep(10)


def start_listening():
    for n in cfg["neighbours"]:
        if n["topic"] not in started:
            started.add(n["topic"])
            threading.Thread(target=listen, args=(n["topic"],), daemon=True).start()


def pinger():
    while True:
        for n in list(cfg["neighbours"]):
            if not n.get("blocked"):
                publish(n, "ping")
        neighbours_event()
        time.sleep(180)


def command(c):
    kind = c.get("cmd")
    if c.get("me"):
        cfg["me"] = c["me"]
    if kind == "invite":
        # un canal y una clave nuevos; el código lleva también de qué lado estará para él
        # (una invitación nueva sustituye a la que aún nadie había usado)
        side = c.get("side", "right")
        code = {"t": "mochi-" + secrets.token_urlsafe(18), "k": secrets.token_urlsafe(24), "n": cfg.get("me", "?"), "s": "left" if side == "right" else "right"}
        # escuchar ya el canal: cuando se una, su primer saludo dirá cómo se llama
        pend = {"name": "(pendiente)", "topic": code["t"], "secret": code["k"], "side": side, "pending": True}
        cfg["neighbours"] = [x for x in cfg["neighbours"] if not x.get("pending")] + [pend]
        save()
        start_listening()
        out(ev="invite", code="mochi:" + base64.urlsafe_b64encode(json.dumps(code).encode()).decode().rstrip("="))
        neighbours_event()
    elif kind == "join":
        try:
            raw = c["code"].strip().removeprefix("mochi:")
            code = json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
            code["t"], code["k"], code["s"]
        except Exception:
            out(ev="error", text="ese código no es válido")
            return
        if find(code["t"]):
            out(ev="error", text="ese código es tuyo (o ya lo habías usado)")
            return
        n = {"name": unique_name(code.get("n"), code["t"]), "topic": code["t"], "secret": code["k"], "side": code["s"]}
        cfg["neighbours"].append(n)
        save()
        start_listening()
        publish(n, "hello")
        neighbours_event()
    elif kind == "send":
        n = by_name(c.get("to"))
        if not n:
            out(ev="error", text=f"no tienes ningún vecino llamado {c.get('to')}")
            return
        ok = publish(n, c.get("type", "visit"), {"mochi": c.get("mochi", {}), "vid": c.get("vid", ""), "refused": c.get("refused", "")})
        out(ev="sent", to=n["name"], type=c.get("type"), ok=ok)
    elif kind == "remove":
        n = next((x for x in cfg["neighbours"] if x["name"] == c.get("name")), None)
        if n:
            if not n.get("pending"):
                publish(n, "bye")   # (que en su casa tampoco salgas)
            cfg["neighbours"].remove(n)
            save()
        neighbours_event()
    elif kind in ("block", "unblock"):
        n = by_name(c.get("name"))
        if n:
            if kind == "block":
                n["blocked"] = True
            else:
                n.pop("blocked", None)
                publish(n, "ping")
            save()
        neighbours_event()
    elif kind == "door":
        cfg["closed"] = not c.get("open", True)
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
