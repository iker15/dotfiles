#!/usr/bin/env python3
# Sigue el log de Minecraft mientras juegas (Prism Launcher o ~/.minecraft), clasifica lo que
# pasa (te mueres, logros, chat, jugadores que entran…) y aplica las reglas de
# reacciones.jsonc (junto a este script; se recargan solas al editarlas). Por cada reacción,
# una línea JSON en stdout para Mochi:
#   {"ev": tipo, "text": …, "cara": …, "ms": …, "hacer": […], "decir": …}
# Los mensajes del log (muertes, logros) salen en inglés: los escribe el servidor.
# Pruebas: mc-watch.py --test "línea del log" [--yo Nombre]
import glob, json, os, re, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.join(HERE, "reacciones.jsonc")
LOGS = [os.path.expanduser("~/.local/share/PrismLauncher/instances/*/minecraft/logs/latest.log"),
        os.path.expanduser("~/.local/share/PrismLauncher/instances/*/.minecraft/logs/latest.log"),
        os.path.expanduser("~/.minecraft/logs/latest.log")]
DEATH = re.compile(r"^(?:was |were |died|drowned|experienced|blew up|burned|went |walked into|hit the ground|fell|froze|starved|suffocated|tried to|withered|discovered|didn't want|left the confines|hit the ground)")
ADV = re.compile(r"^(\S+) has (made the advancement|completed the challenge|reached the goal) \[(.+)\]")
CHAT = re.compile(r"^(?:\[[^\]]*\] )*<([^>]+)> (.*)$")
JOIN = re.compile(r"^(\S+) joined the game$")
LEAVE = re.compile(r"^(\S+) left the game$")


class Rules:
    def __init__(self):
        self.rules, self.mtime = [], 0

    def load(self):
        try:
            m = os.path.getmtime(RULES)
        except OSError:
            return
        if m == self.mtime:
            return
        self.mtime = m
        try:
            text = open(RULES).read()
            # quitar comentarios // (fuera de cadenas)
            text = re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*', lambda g: g.group(1) or "", text)
            self.rules = json.loads(text).get("reglas", [])
        except Exception as e:
            print(json.dumps({"ev": "error", "text": f"reacciones.jsonc: {e}"}), flush=True)

    def match(self, kind, text, me, players):
        self.load()
        others = "|".join(re.escape(p) for p in sorted(players) if p != me) or "(?!)"
        for r in self.rules:
            if r.get("si") != kind:
                continue
            pat = r.get("texto")
            if pat:
                pat = pat.replace("{yo}", re.escape(me or "")).replace("{jugador}", f"(?:{others})")
                try:
                    if not re.search(pat, text or "", re.I):
                        continue
                except re.error:
                    continue
            yield r
            if not r.get("seguir"):
                return


class Watcher:
    def __init__(self):
        self.rules = Rules()
        self.me = None
        self.players = set()

    def emit(self, kind, text=""):
        for r in self.rules.match(kind, text, self.me, self.players):
            print(json.dumps({"ev": kind, "text": text, "cara": r.get("cara", ""), "ms": r.get("ms", 2000),
                              "hacer": r.get("hacer", []), "decir": r.get("decir", "")}), flush=True)

    def handle(self, line):
        self.emit("linea", line)
        m = re.search(r"Setting user: (\S+)", line)
        if m:
            self.me = m.group(1)
            return
        if "Connecting to " in line or "Starting integrated minecraft server" in line:
            self.players = set()
            self.emit("entrar")
            return
        if re.search(r"\]: Stopping!$", line):
            self.emit("salir")
            return
        m = re.search(r"\[CHAT\] (.*)$", line)
        if not m or not self.me:
            return
        msg, me = m.group(1).strip(), self.me
        a = ADV.match(msg)
        if a:
            if a.group(1) == me:
                kind = {"made the advancement": "logro", "completed the challenge": "reto", "reached the goal": "objetivo"}[a.group(2)]
                self.emit(kind, a.group(3))
            return
        j = JOIN.match(msg)
        if j:
            self.players.add(j.group(1))
            if j.group(1) != me:
                self.emit("conecta", j.group(1))
            return
        lv = LEAVE.match(msg)
        if lv:
            self.players.discard(lv.group(1))
            if lv.group(1) != me:
                self.emit("desconecta", lv.group(1))
            return
        c = CHAT.match(msg)
        if c:
            who, text = c.group(1), c.group(2)
            if who == me:
                self.emit("mio", text)
                return
            self.players.add(who)
            short = me.lower()[:4]
            if me.lower() in text.lower() or re.search(rf"\b{re.escape(short)}", text.lower()):
                self.emit("mencion", text)
            else:
                self.emit("chat", text)
            return
        if msg.startswith(me + " ") and DEATH.match(msg[len(me) + 1:]):
            self.emit("muerte", msg[len(me) + 1:])
            return
        first = msg.split(" ", 1)
        if len(first) == 2 and DEATH.match(first[1]) and re.match(r"^\w{3,16}$", first[0]):
            self.players.add(first[0])
            if re.search(rf"\bby {re.escape(me)}\b", first[1]):
                self.emit("matar", msg)
            else:
                self.emit("otro-muere", msg)

    def newest(self):
        files = [f for pat in LOGS for f in glob.glob(pat)]
        return max(files, key=os.path.getmtime) if files else None

    def follow(self, path):
        with open(path, errors="replace") as f:
            f.seek(0, os.SEEK_END)
            idle = 0
            while True:
                line = f.readline()
                if not line:
                    time.sleep(0.4)
                    idle += 0.4
                    # el log se ha rotado (juego reiniciado) o hay otro más nuevo
                    if idle > 5:
                        idle = 0
                        if self.newest() != path or os.path.getsize(path) < f.tell():
                            return
                    continue
                idle = 0
                self.handle(line.rstrip("\n"))

    def run(self):
        while True:
            p = self.newest()
            # solo si se está escribiendo ahora (jugando)
            if p and time.time() - os.path.getmtime(p) < 120:
                try:
                    with open(p, errors="replace") as f:
                        for line in f:
                            m = re.search(r"Setting user: (\S+)", line)
                            if m:
                                self.me = m.group(1)
                            j = re.search(r"\[CHAT\] (\S+) joined the game$", line)
                            if j:
                                self.players.add(j.group(1))
                            lv = re.search(r"\[CHAT\] (\S+) left the game$", line)
                            if lv:
                                self.players.discard(lv.group(1))
                except OSError:
                    pass
                self.follow(p)
            else:
                time.sleep(8)


if __name__ == "__main__":
    w = Watcher()
    if len(sys.argv) > 2 and sys.argv[1] == "--test":
        args = sys.argv[2:]
        if "--yo" in args:
            i = args.index("--yo")
            w.me = args[i + 1]
            args = args[:i] + args[i + 2:]
        w.me = w.me or "Ikerchito"
        for line in args:
            w.handle(line)
        sys.exit(0)
    # (casi nunca escribe, así que no se entera de que Mochi se ha cerrado: si cambia de padre,
    # es que lo han dejado huérfano, y se va; si no, se acumulaban uno por cada reinicio)
    parent = os.getppid()

    def orphan_guard():
        while os.getppid() == parent:
            time.sleep(3)
        os._exit(0)

    threading.Thread(target=orphan_guard, daemon=True).start()
    try:
        w.run()
    except KeyboardInterrupt:
        pass
