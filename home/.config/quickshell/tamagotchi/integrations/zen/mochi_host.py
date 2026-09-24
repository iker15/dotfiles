#!/usr/bin/env python3
# Host nativo de la extensión de Zen (native messaging): puente entre el navegador y Mochi.
#  - Lo que manda la extensión (el vídeo que estás viendo: dónde está, si va, si es un anuncio,
#    los momentos más vistos…) → $XDG_RUNTIME_DIR/mochi-browser.json (lo lee Mochi).
#  - A la extensión (para la nueva pestaña): el estado de Mochi (mochi-state.json) y los
#    colores de Caelestia (scheme.json), cada vez que cambian.
#  - Acciones desde la nueva pestaña (llamarlo, hablarle…) → qs ipc.
import json, os, struct, subprocess, sys, threading, time

RUN = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
OUT = os.path.join(RUN, "mochi-browser.json")
STATE = os.path.join(RUN, "mochi-state.json")
SCHEME = os.path.expanduser("~/.local/state/caelestia/scheme.json")
lock = threading.Lock()


def send(msg):
    data = json.dumps(msg).encode()
    with lock:
        sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
        sys.stdout.buffer.flush()


def read():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return None
    n = struct.unpack("@I", raw)[0]
    return json.loads(sys.stdin.buffer.read(n))


def write_atomic(path, text):
    tmp = f"{path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def watcher():
    last = None
    while True:
        try:
            st = json.load(open(STATE))
        except Exception:
            st = None
        try:
            sc = json.load(open(SCHEME))
            colours = {k: "#" + v for k, v in sc["colours"].items()}
            mode = sc.get("mode", "dark")
        except Exception:
            colours, mode = {}, "dark"
        cur = json.dumps([st, colours, mode], sort_keys=True)
        if cur != last:
            last = cur
            send({"type": "state", "state": st, "colours": colours, "mode": mode})
        time.sleep(1)


def main():
    threading.Thread(target=watcher, daemon=True).start()
    while True:
        msg = read()
        if msg is None:
            break
        kind = msg.get("type")
        if kind == "video":
            msg["ts"] = time.time() * 1000
            write_atomic(OUT, json.dumps(msg))
        elif kind == "gone":
            write_atomic(OUT, json.dumps({"type": "gone", "ts": time.time() * 1000}))
        elif kind == "ipc" and msg.get("args"):
            # solo órdenes de la lista (la página no puede pedir cualquier cosa)
            args = [str(a) for a in msg["args"]]
            if args[0] in ("appear", "talk", "nest", "heart", "pokeFromTab"):
                subprocess.Popen(["qs", "-c", "tamagotchi", "ipc", "call", "pet", *args],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
