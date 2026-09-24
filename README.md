# dotfiles

Mi setup de **CachyOS + Hyprland + Caelestia (quickshell)**.

## Instalar en un PC nuevo (el tuyo o el de un amigo)

1. Instala CachyOS desde la ISO (los drivers de la gráfica los pone el instalador; el
   script no instala drivers ni kernels, así que vale para cualquier PC).
2. Un solo comando:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/iker15/dotfiles/main/bootstrap.sh)
```

(Si el repo es privado, antes: `sudo pacman -S github-cli && gh auth login && gh auth setup-git`,
con una cuenta que tenga acceso, y luego `git clone https://github.com/iker15/dotfiles ~/dotfiles && ~/dotfiles/install.sh`.)

El script instala los paquetes (`pkglist.txt` oficiales, `aurlist.txt` AUR),
enlaza todo lo de `home/` a `~` con symlinks (lo que ya existiera va a
`~/.dotfiles-backup-*`), activa servicios y pone fish como shell. Cada uno crea su
propio Mochi desde el dashboard (no viene ninguno hecho).

## Cómo funciona

Las configs viven en `~/dotfiles/home/` y `~/.config/<cosa>` es un symlink hacia
aquí, así que cualquier cambio queda en el repo directamente.

```bash
./sync.sh "mensaje"   # actualiza listas de paquetes, commit y push
```

## Qué NO está aquí

Claves SSH/GPG, tokens (`.claude.json`, Discord, Spotify), historial del
navegador. Eso se copia a mano.
