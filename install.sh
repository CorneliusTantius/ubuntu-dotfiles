#!/usr/bin/env bash
# install.sh: one-shot Nord rice for Ubuntu 26.04 GNOME (bash, Kitty, Starship, Fastfetch).
#
# Asks before each section. Needs a terminal, because answers are read from /dev/tty.
# Copies configs from this folder into $HOME and overwrites existing files without a backup:
#   ~/.config/kitty/kitty.conf, ~/.config/starship.toml, ~/.config/fastfetch/config.jsonc
# Loads touchpad and dock settings from gnome/*.dconf (snapshots of the current setup).
# Appends the Starship init line and a `..` alias to ~/.bashrc, once each.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
NORDIC_REPO="https://github.com/EliverLara/Nordic.git"
PAPIRUS_NORD_REPO="https://github.com/Adapta-Projects/Papirus-Nord.git"
KITTY_KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty/"

if ! (: < /dev/tty) 2> /dev/null; then
    echo "Run install.sh from a terminal. It asks before each step." >&2
    exit 1
fi

ask() {
    local reply
    read -rp "$1 [y/N] " reply < /dev/tty
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_packages() {
    sudo apt-get update
    sudo apt-get install -y kitty starship fastfetch papirus-icon-theme git curl fontconfig dconf-cli
}

install_nerd_font() {
    local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
    mkdir -p "$font_dir"
    curl -fL --progress-bar "$NERD_FONT_URL" -o "$WORK/JetBrainsMono.tar.xz"
    tar -xf "$WORK/JetBrainsMono.tar.xz" -C "$font_dir"
    fc-cache -f "$HOME/.local/share/fonts"
}

install_nordic() {
    git clone --depth 1 "$NORDIC_REPO" "$WORK/Nordic"
    rm -rf "$WORK/Nordic/.git"
    mkdir -p "$HOME/.themes"
    rm -rf "$HOME/.themes/Nordic"
    mv "$WORK/Nordic" "$HOME/.themes/Nordic"
}

install_papirus_nord() {
    if [[ ! -d /usr/share/icons/Papirus ]]; then
        echo "Papirus base theme is missing. Run the packages step first." >&2
        return 1
    fi
    git clone --depth 1 "$PAPIRUS_NORD_REPO" "$WORK/Papirus-Nord"
    # Upstream Install.sh copies files into /usr/share/icons and /usr/bin, so it needs sudo.
    # Its first prompt asks about Linux Universe. "N" selects the standard papirus-folders script.
    sudo -v
    (cd "$WORK/Papirus-Nord" && printf 'N\n' | sudo bash ./install)
}

install_dotfiles() {
    mkdir -p "$HOME/.config/kitty" "$HOME/.config/fastfetch"
    cp -f "$DOTFILES/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    cp -f "$DOTFILES/starship/starship.toml" "$HOME/.config/starship.toml"
    cp -f "$DOTFILES/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"

    touch "$HOME/.bashrc" "$HOME/.inputrc"
    if ! grep -qF 'starship init bash' "$HOME/.bashrc"; then
        printf '\neval "$(starship init bash)"\n' >> "$HOME/.bashrc"
    fi
    if ! grep -qF "alias ..='cd ..'" "$HOME/.bashrc"; then
        printf "alias ..='cd ..'\n" >> "$HOME/.bashrc"
    fi
    # Tab completion ignores case (readline), and globs like *.txt also match *.TXT.
    if ! grep -qF 'completion-ignore-case' "$HOME/.inputrc"; then
        printf 'set completion-ignore-case on\n' >> "$HOME/.inputrc"
    fi
    if ! grep -qF 'nocaseglob' "$HOME/.bashrc"; then
        printf 'shopt -s nocaseglob\n' >> "$HOME/.bashrc"
    fi
}

apply_gnome_settings() {
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
    if [[ -d "$HOME/.themes/Nordic" ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme 'Nordic'
    fi
    if [[ -d /usr/share/icons/Papirus ]]; then
        gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
    fi
    # Solid pitch black background instead of an image, for both light and dark mode.
    gsettings set org.gnome.desktop.background picture-uri ''
    gsettings set org.gnome.desktop.background picture-uri-dark ''
    gsettings set org.gnome.desktop.background picture-options 'none'
    gsettings set org.gnome.desktop.background color-shading-type 'solid'
    gsettings set org.gnome.desktop.background primary-color '#000000'
}

add_kitty_keybinding() {
    local existing updated key_schema
    existing="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
    if [[ "$existing" != *"$KITTY_KEY_PATH"* ]]; then
        if [[ "$existing" == "@as []" || "$existing" == "[]" ]]; then
            updated="['$KITTY_KEY_PATH']"
        else
            updated="${existing%]}, '$KITTY_KEY_PATH']"
        fi
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated"
    fi
    key_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KITTY_KEY_PATH"
    gsettings set "$key_schema" name 'Kitty'
    gsettings set "$key_schema" command 'kitty'
    gsettings set "$key_schema" binding '<Super>Return'
}

apply_keys_touchpad_dock() {
    dconf load /org/gnome/desktop/peripherals/touchpad/ < "$DOTFILES/gnome/touchpad.dconf"
    dconf load /org/gnome/shell/extensions/dash-to-dock/ < "$DOTFILES/gnome/dock.dconf"
    # Dash to Dock binds Super+Q to show the dock. Clear it so Super+Q can close windows.
    gsettings set org.gnome.shell.extensions.dash-to-dock shortcut "[]"
    gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']"
    add_kitty_keybinding
}

make_kitty_default_terminal() {
    if ! command -v kitty > /dev/null; then
        echo "Kitty is not installed. Run step 1 first." >&2
        return 1
    fi
    # Ubuntu 26.04 reads the default terminal from xdg-terminals.list. Ctrl+Alt+T goes through it.
    mkdir -p "$HOME/.config"
    echo "kitty.desktop" > "$HOME/.config/xdg-terminals.list"
    # Scripts and older tools use the x-terminal-emulator alternative.
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 60
    sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty
}

remove_other_terminals() {
    if ! command -v kitty > /dev/null; then
        echo "Kitty is not installed. Run steps 1 and 8 first." >&2
        return 1
    fi
    if [[ "$(readlink -f /usr/bin/x-terminal-emulator)" != "/usr/bin/kitty" ]]; then
        echo "Kitty is not the default terminal yet. Run step 8 first." >&2
        return 1
    fi
    # apport-gtk depends on a terminal from x-terminal-emulator. Removing it with Ptyxis
    # lets apt drop both without installing GNOME Terminal in their place.
    sudo apt-get remove -y ptyxis apport-gtk gnome-terminal gnome-terminal-data
}

main() {
    echo "Nord rice for Ubuntu 26.04 GNOME. Each step asks first."

    if ask "1. Install apt packages (kitty, starship, fastfetch, papirus-icon-theme, git, curl, fontconfig, dconf-cli)? Uses sudo."; then
        install_packages
    fi
    if ask "2. Download JetBrains Mono Nerd Font from github.com/ryanoasis/nerd-fonts?"; then
        install_nerd_font
    fi
    if ask "3. Download the Nordic GTK theme from github.com/EliverLara/Nordic into ~/.themes?"; then
        install_nordic
    fi
    if ask "4. Download Papirus-Nord from github.com/Adapta-Projects/Papirus-Nord and run its Install.sh with sudo?"; then
        install_papirus_nord
    fi
    if ask "5. Copy kitty, starship and fastfetch configs into ~/.config (overwrites existing files, no backup) and add Starship, a \`..\` alias, and case-insensitive completion and globbing to your shell setup?"; then
        install_dotfiles
    fi
    if ask "6. Set GNOME to dark mode, Nordic GTK, Papirus icons, the Nerd Font as monospace and a pitch black wallpaper?"; then
        apply_gnome_settings
    fi
    if ask "7. Set touchpad scrolling and dock layout to your current setup, Super+Return for Kitty, and Super+Q to close windows instead of Alt+F4?"; then
        apply_keys_touchpad_dock
    fi
    if ask "8. Make Kitty the default terminal (Ctrl+Alt+T and x-terminal-emulator)? Uses sudo."; then
        make_kitty_default_terminal
    fi
    if ask "9. Remove Ptyxis, GNOME Terminal and apport-gtk (the crash-report popup), leaving only Kitty? Uses sudo."; then
        remove_other_terminals
    fi

    echo "Done. Log out and back in so the GTK, icon and keybinding changes apply everywhere."
    echo "Open bash sessions: run  source ~/.bashrc && bind -f ~/.inputrc"
    echo "Open Kitty windows: press Ctrl+Shift+F5 to reload kitty.conf, or close and reopen them."
    echo "Super+Return opens Kitty. Ctrl+Alt+T opens Kitty too, once step 8 has run."
}

main
