# dotfiles

Mi setup de **CachyOS + Hyprland + Caelestia (quickshell)**.

## Instalar en un PC nuevo

1. Instala CachyOS desde la ISO (drivers NVIDIA los pone el instalador).
2. Después:

```bash
git clone https://github.com/iker15/dotfiles ~/dotfiles
cd ~/dotfiles && ./install.sh
```

El script instala los paquetes (`pkglist.txt` oficiales, `aurlist.txt` AUR),
enlaza todo lo de `home/` a `~` con symlinks (lo que ya existiera va a
`~/.dotfiles-backup-*`), activa servicios y pone fish como shell.

## Cómo funciona

Las configs viven en `~/dotfiles/home/` y `~/.config/<cosa>` es un symlink hacia
aquí, así que cualquier cambio queda en el repo directamente.

```bash
./sync.sh "mensaje"   # actualiza listas de paquetes, commit y push
```

## Qué NO está aquí

Claves SSH/GPG, tokens (`.claude.json`, Discord, Spotify), historial del
navegador. Eso se copia a mano.
