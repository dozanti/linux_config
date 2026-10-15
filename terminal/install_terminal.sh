#!/bin/bash
# Fresh-install bootstrap for Zsh + Oh My Zsh + Powerlevel10k + fnm + Ptyxis/GNOME Terminal.
set -euo pipefail

echo "[INFO] Installing dependencies..."
sudo apt update
sudo apt install -y zsh git curl unzip fonts-powerline tree

echo "[INFO] Installing fnm..."
FNM_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
if command -v fnm >/dev/null 2>&1 || [[ -x "$FNM_INSTALL_DIR/fnm" ]]; then
  echo "[INFO] fnm already present, skipping installation."
else
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi
export PATH="$FNM_INSTALL_DIR:$PATH"
eval "$(fnm env --shell bash)"
fnm install --lts --use
fnm default "$(fnm current)"

echo "[INFO] Installing Oh My Zsh..."
OMZ_INSTALLER="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"
export RUNZSH=no
sh "$OMZ_INSTALLER"
rm -f "$OMZ_INSTALLER"

echo "[INFO] Installing Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ -d "$P10K_DIR" ]]; then
  echo "[INFO] Powerlevel10k already present, skipping clone."
else
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

echo "[INFO] Copying configuration files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in .zshrc .p10k.zsh; do
  if [[ -f "$HOME/$f" ]]; then
    backup="$HOME/$f.bak.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] Backing up existing ~/$f to $backup"
    cp "$HOME/$f" "$backup"
  fi
  cp "$SCRIPT_DIR/$f" "$HOME/$f"
done

echo "[INFO] Installing JetBrains Mono Nerd Font..."
mkdir -p "$HOME/.local/share/fonts"
FONT_ZIP="$(mktemp --suffix=.zip)"
curl -fLo "$FONT_ZIP" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o "$FONT_ZIP" -d "$HOME/.local/share/fonts"
rm -f "$FONT_ZIP"
fc-cache -fv

echo "[INFO] Installing zsh-syntax-highlighting..."
SYNTAX_HL_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
if [[ -d "$SYNTAX_HL_DIR" ]]; then
  echo "[INFO] zsh-syntax-highlighting already present, skipping clone."
else
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HL_DIR"
fi

echo "[INFO] Installing Papirus icon theme (latest release)..."
PAPIRUS_TAG=$(curl -fsSL https://api.github.com/repos/PapirusDevelopmentTeam/papirus-icon-theme/releases/latest \
  | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
PAPIRUS_TAG="${PAPIRUS_TAG:-master}"
curl -fsSL https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | TAG="$PAPIRUS_TAG" sh

echo "[INFO] Setting Zsh as the default shell..."
chsh -s "$(command -v zsh)"

TERMINAL_FONT='JetBrainsMono Nerd Font 12'

has_schema() {
  gsettings list-schemas | grep -xF "$1" >/dev/null
}

configure_ptyxis() {
  local profile_id profile_ids
  profile_id=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")

  # Ptyxis creates its first profile lazily on first launch, so a fresh
  # install has none yet; create it here so the palette can be applied.
  if [[ -z "$profile_id" ]]; then
    profile_id=$(tr -d '-' </proc/sys/kernel/random/uuid)
    profile_ids=$(gsettings get org.gnome.Ptyxis profile-uuids)
    if [[ "$profile_ids" == *"[]" ]]; then
      profile_ids="['$profile_id']"
    else
      profile_ids="${profile_ids%]}, '$profile_id']"
    fi
    gsettings set org.gnome.Ptyxis profile-uuids "$profile_ids"
    gsettings set org.gnome.Ptyxis default-profile-uuid "$profile_id"
  fi

  gsettings set org.gnome.Ptyxis use-system-font false
  gsettings set org.gnome.Ptyxis font-name "$TERMINAL_FONT"
  gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$profile_id/" palette 'Vs Code'
}

configure_gnome_terminal() {
  local profile_id profile_path
  profile_id=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
  profile_path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile_id/"

  gsettings set "$profile_path" use-system-font false
  gsettings set "$profile_path" font "$TERMINAL_FONT"
  gsettings set "$profile_path" use-theme-colors false
  gsettings set "$profile_path" background-color '#1E1E1E'
  gsettings set "$profile_path" foreground-color '#C0C0C0'
}

if command -v gsettings >/dev/null 2>&1; then
  if has_schema org.gnome.Ptyxis; then
    echo "[INFO] Configuring Ptyxis..."
    configure_ptyxis
  elif has_schema org.gnome.Terminal.ProfilesList; then
    echo "[INFO] Configuring GNOME Terminal..."
    configure_gnome_terminal
  else
    echo "[INFO] Neither Ptyxis nor GNOME Terminal found, skipping terminal styling."
  fi

  if has_schema org.gnome.desktop.interface; then
    echo "[INFO] Setting Papirus as the active icon theme..."
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
  else
    echo "[INFO] GNOME interface settings not found, skipping icon theme selection."
  fi
else
  echo "[INFO] gsettings not found, skipping terminal styling and icon theme selection."
fi

echo "[INFO] Installation complete."
echo "[INFO] Log out or restart to apply all changes."
