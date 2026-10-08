# dotfiles de iker (CachyOS + Hyprland + Caelestia)

Repo: `git@github.com:iker15/dotfiles.git` (rama `main`). Se clona en `~/dotfiles` y
desde ahí se enlaza todo con symlinks; **los ficheros reales viven en el repo**, no en
`~/.config`. Editar `~/.config/hypr/...` es editar `~/dotfiles/home/.config/hypr/...`.

## Qué hay

- `home/` — lo que se enlaza al `$HOME` (`.config/*`, `.local/bin/*`, `.zshrc`).
- `pkglist.txt` / `aurlist.txt` — paquetes. Los rehace `sync.sh` con
  `pacman -Qqen` / `-Qqem`. **Ojo: ver «la trampa de sync.sh» más abajo antes de
  ejecutarlo.** Hasta que eso se arregle, editar a mano es legítimo para un paquete que
  la configuración necesita de verdad.
- `install.sh` — despliegue completo. `bootstrap.sh` lo clona y lo ejecuta de un tirón.
- `sync.sh` — rehace las listas, comitea y empuja.
- `system/` — Plymouth (tema Mochi) y fondo de Limine. Piden sudo.

## Cómo se despliega

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/iker15/dotfiles/main/bootstrap.sh)
```

`install.sh` hace, en este orden: actualizar sistema + paquetes oficiales → paru →
paquetes del AUR → **comprobar que los del AUR siguen encajando** → symlinks (lo que
había se guarda en `~/.dotfiles-backup-<fecha>`) → servicios → voz de Mochi → Plymouth
y Limine → integraciones en apps → wallpapers → `chsh` a fish. Es idempotente: se puede
volver a lanzar.

## La trampa de `sync.sh` (2026-10-08)

`sync.sh` **sobrescribe** las listas con `pacman -Qqen` / `-Qqem` de la máquina donde
se ejecuta. Dos problemas, y el segundo muerde de verdad:

1. Cada PC tiene paquetes propios. Ejecutarlo en el sobremesa mete `grub`, `amd-ucode`,
   `nvidia-open-dkms`, `discord`, `minecraft-launcher`, `ollama`… Los de hardware y
   arranque los filtra `install.sh` con `HW`/`SYS`, así que son ruido inofensivo.
2. **`-Qqen` sólo lista los explícitos.** Un paquete que en esta máquina entró como
   dependencia de otro desaparece de la lista aunque la configuración lo necesite. Medido
   el 2026-10-08 en el sobremesa: se perderían **37**, entre ellos `fish`, `curl`,
   `pipewire`, `pipewire-audio`, `bat`, `eza`, `jq`, `matugen`. Aquí `fish` lo arrastran
   `cachyos-fish-config` y `caelestia-shell`, así que no es explícito — y `install.sh`
   termina con `chsh -s /bin/fish`.

Mientras `sync.sh` siga sobrescribiendo: **no ejecutarlo desde una máquina distinta de
la que generó las listas**, y comparar antes con
`comm -23 <(sort pkglist.txt) <(pacman -Qqen | sort)` para ver qué se perdería.

## Decisiones que no hay que deshacer

- **El escritorio necesita `quickshell-git`, no `quickshell`.** Otros paquetes (el
  `noctalia-qs` que trae la edición Hyprland de CachyOS) dicen *proveer* quickshell-git
  pero Caelestia no arranca con ellos. De ahí el `paru -S aur/<pkg>` con prefijo `aur/`
  y el `pacman -Rdd` de los impostores al principio del paso del AUR.
- **Paso de verificación del AUR (añadido 2026-10-08).** Un paquete del AUR compilado
  hace meses puede quedarse roto al actualizar el sistema sin que pacman lo note: su
  versión no ha cambiado. Pasó con `quickshell-git` (ver abajo). El paso recorre
  `aurlist.txt`, mira con `ldd -r` los **ejecutables** de cada paquete instalado y
  recompila el que tenga símbolos sin resolver. Sólo ejecutables a propósito: en una
  librería suelta los símbolos sin resolver son normales (los aporta quien la carga),
  y mirarlas daba falsos positivos.
- **Conflictos de paquetes:** se detectan en los dos sentidos. `matugen-bin` declara que
  choca con `matugen` pero no al revés, así que mirando sólo la lista no se ve y pacman
  se para con `--noconfirm`. Se ignoran los conflictos con versión (`cryptsetup<2.8`).
- **Filtros `HW` y `SYS` en `install.sh`:** fuera drivers, kernels, microcódigo, gestor
  de arranque y el escritorio que eligió el instalador de CachyOS. Eso es de cada PC.
- **Teclado:** en el repo va `us` porque es el que usa iker a propósito. `install.sh`
  sólo lo cambia al del sistema si `$USER != iker`.
- **`default.target.wants/` sí va versionado** (unidades propias: `caelestia-dark.path`,
  `appimagelauncherd`). Los enlaces a unidades del sistema que crea
  `systemctl --user enable` (pipewire, wireplumber) están en `.gitignore`: son estado
  que install.sh recrea.

## Historial de averías

### 2026-10-08 — El escritorio se quedó «sin cambiar» tras instalar los dotfiles

Síntoma: tras el despliegue y el reinicio, Hyprland arrancaba pelado — sin barra, sin
Mochi, sin lanzador. Parecía que los dotfiles no se habían aplicado.

Se habían aplicado: 222/224 paquetes oficiales, 14/15 del AUR, las 29 configs enlazadas,
Hyprland leyendo `hyprland.lua` con cero errores de configuración y el hook
`hyprland.start` ejecutado entero (keyring, polkit, cliphist, mpris-proxy, cursores).

Causa raíz: `quickshell-git` estaba compilado del **1 jun 2026**. El `pacman -Syu` del
instalador subió `qt6-base` a **6.12.0**. Quickshell usa la API privada de Qt, que rompe
ABI en cada versión; en 6.12 el símbolo
`_ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate` pasó a exportarse como
público (`@@Qt_6`) y el binario viejo lo pedía como `@Qt_6_PRIVATE_API`. Resultado:

```
qs: symbol lookup error: qs: undefined symbol: ... version Qt_6_PRIVATE_API
```

`caelestia shell -d` se ejecutaba y moría al instante, sin dejar nada en el log de
Hyprland. Y el paso del AUR se lo saltaba por estar «ya instalado».

Arreglo: `paru -S --rebuild aur/quickshell-git` → `quickshell-git 0.3.2.r0.g4f508be`,
`ldd -r /usr/bin/qs` sin símbolos pendientes, `qs -c caelestia -n -d` arrancando sin
errores de QML. Y el paso de verificación del AUR en `install.sh` para que no vuelva a
pasar en el portátil.

**Regla general:** si el escritorio arranca pelado, lo primero es
`caelestia shell -d` a mano en una terminal y leer lo que escupe. Hyprland no registra
el fallo de lo que lanza.

## Pendientes

- `gammastep` lo llama `hyprland/execs.lua` al arrancar. Instalado en el sobremesa y
  añadido **a mano** a `pkglist.txt` el 2026-10-08 (a mano a propósito: ver la trampa de
  `sync.sh`). Faltaba desde siempre: la luz nocturna nunca se encendía.
- ~~`caelestia-firefox-theme`~~ **borrado del AUR** (comprobado 2026-10-08: la API
  devuelve `resultcount: 0`, y no hay paquete renombrado que lo sustituya). Quitado de
  `aurlist.txt`. **No volver a añadirlo**: si sigue instalado en el portátil, el
  `pacman -Qqem` de `sync.sh` lo mete otra vez desde allí — desinstalarlo
  (`paru -Rns caelestia-firefox-theme`) para que no reaparezca.
- `matugen` y `jre25-openjdk` se saltan a propósito: chocan con `matugen-bin` y `jdk25`,
  que ya están. No es un fallo.
- **`sync.sh` sigue sobrescribiendo las listas.** Decidir si pasa a fusionar (unión con
  lo que ya hay, para no perder nunca lo que declaró otra máquina) o se queda así con el
  aviso. Sin decidir.
