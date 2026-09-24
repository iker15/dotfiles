#!/usr/bin/env bash
# Un solo comando en una CachyOS recién instalada:
#   bash <(curl -fsSL https://raw.githubusercontent.com/iker15/dotfiles/main/bootstrap.sh)
# Clona los dotfiles en ~/dotfiles (o los actualiza) y ejecuta install.sh.
set -euo pipefail
repo=https://github.com/iker15/dotfiles.git
sudo pacman -S --needed --noconfirm git
if [[ -d ~/dotfiles/.git ]]; then
    git -C ~/dotfiles pull --ff-only
else
    git clone "$repo" ~/dotfiles
fi
exec ~/dotfiles/install.sh
