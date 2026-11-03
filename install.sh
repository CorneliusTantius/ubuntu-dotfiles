#!/usr/bin/env bash
# install.sh: one-shot Nord rice for Ubuntu 26.04 GNOME (bash, Kitty, Starship, Fastfetch).
#
# Asks before each step and redraws a progress dashboard after each one.
# Needs a terminal, because answers are read from /dev/tty.
# Copies configs from this folder into $HOME and overwrites existing files without a backup.
# Loads touchpad and dock settings from gnome/*.dconf (snapshots of the current setup).
# Appends shell settings to ~/.bashrc and ~/.inputrc, once each.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
KITTY_KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty/"

if ! (: < /dev/tty) 2> /dev/null; then
    echo "Run install.sh from a terminal. It asks before each step." >&2
    exit 1
fi

# Nord palette as truecolor escapes. Plain text when output is not a terminal.
if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
    FROST=$'\033[38;2;136;192;208m'
    TEAL=$'\033[38;2;143;188;187m'
    GREEN=$'\033[38;2;163;190;140m'
    RED=$'\033[38;2;191;97;106m'
    YELLOW=$'\033[38;2;235;203;139m'
    MUTED=$'\033[38;2;76;86;106m'
    SNOW=$'\033[38;2;216;222;233m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
    IS_TTY=1
else
    FROST="" TEAL="" GREEN="" RED="" YELLOW="" MUTED="" SNOW="" BOLD="" RESET=""
    IS_TTY=0
fi

TITLES=(
    "Packages"
    "Nerd Font"
    "Dotfiles and shell"
    "GNOME look"
    "Keys, touchpad, dock"
    "Default terminal"
    "Other terminals"
)
TAGLINES=(
    "kitty, starship, fastfetch, git, curl, dconf-cli (sudo)"
    "JetBrains Mono Nerd Font, downloaded from GitHub"
    "configs into ~/.config, shell aliases, case-insensitive bash"
    "dark mode, blue accent, Nord background, Nerd Font monospace"
    "touchpad scrolling, dock layout, Super+Return, Super+Q"
    "Kitty for Ctrl+Alt+T and x-terminal-emulator (sudo)"
    "remove Ptyxis, GNOME Terminal and apport-gtk (sudo)"
)
STEP_FUNCS=(
    install_packages
    install_nerd_font
    install_dotfiles
    apply_gnome_settings
    apply_keys_touchpad_dock
    make_kitty_default_terminal
    remove_other_terminals
)
STATUS=()
DURATION=()
for _ in "${TITLES[@]}"; do
    STATUS+=(pending)
    DURATION+=(0)
done

ask() {
    local reply
    printf '  %s❯%s Run this step? %s[y/N]%s ' "$FROST" "$RESET" "$MUTED" "$RESET"
    read -r reply < /dev/tty
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_packages() {
    sudo apt-get update
    sudo apt-get install -y kitty starship fastfetch git curl fontconfig dconf-cli
}

install_nerd_font() {
    local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
    mkdir -p "$font_dir"
    curl -fL --progress-bar "$NERD_FONT_URL" -o "$WORK/JetBrainsMono.tar.xz"
    tar -xf "$WORK/JetBrainsMono.tar.xz" -C "$font_dir"
    fc-cache -f "$HOME/.local/share/fonts"
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
    # Yaru with a blue accent. GTK3 apps take the accent from the theme name, libadwaita apps from accent-color.
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-blue'
    gsettings set org.gnome.desktop.interface accent-color 'blue'
    gsettings reset org.gnome.desktop.interface icon-theme
    # Solid Nord background (Polar Night, #2E3440) instead of an image, for both light and dark mode.
    gsettings set org.gnome.desktop.background picture-uri ''
    gsettings set org.gnome.desktop.background picture-uri-dark ''
    gsettings set org.gnome.desktop.background picture-options 'none'
    gsettings set org.gnome.desktop.background color-shading-type 'solid'
    gsettings set org.gnome.desktop.background primary-color '#2E3440'
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
        echo "Kitty is not installed. Run the packages step first." >&2
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
        echo "Kitty is not installed. Run the packages step first." >&2
        return 1
    fi
    if [[ "$(readlink -f /usr/bin/x-terminal-emulator)" != "/usr/bin/kitty" ]]; then
        echo "Kitty is not the default terminal yet. Run the default terminal step first." >&2
        return 1
    fi
    # apport-gtk depends on a terminal from x-terminal-emulator. Removing it with Ptyxis
    # lets apt drop both without installing GNOME Terminal in their place.
    sudo apt-get remove -y ptyxis apport-gtk gnome-terminal gnome-terminal-data
}

# ---- dashboard ----------------------------------------------------------

clear_screen() {
    if (( IS_TTY )); then
        printf '\033[H\033[2J\033[3J'
    fi
}

rule() {
    printf '─%.0s' $(seq 1 "$1")
}

banner() {
    printf '%s╭%s╮%s\n' "$FROST" "$(rule 42)" "$RESET"
    printf '%s│%s%-42s%s│%s\n' "$FROST" "$BOLD$SNOW" "    N O R D   R I C E" "$RESET$FROST" "$RESET"
    printf '%s│%s%-42s%s│%s\n' "$FROST" "$TEAL" "    Ubuntu 26.04 * GNOME * Kitty" "$RESET$FROST" "$RESET"
    printf '%s╰%s╯%s\n' "$FROST" "$(rule 42)" "$RESET"
}

render() {
    local total=${#TITLES[@]} done_count=0 filled bar i icon color line
    for i in "${!TITLES[@]}"; do
        if [[ "${STATUS[i]}" == done ]]; then
            done_count=$((done_count + 1))
        fi
    done
    filled=$((done_count * 30 / total))
    bar=""
    for ((i = 0; i < 30; i++)); do
        if ((i < filled)); then
            bar+="█"
        else
            bar+="░"
        fi
    done

    clear_screen
    echo
    banner
    echo
    printf '  %sProgress%s  %s%s%s  %s%d of %d%s\n\n' \
        "$BOLD" "$RESET" "$GREEN" "$bar" "$RESET" "$SNOW" "$done_count" "$total" "$RESET"
    for i in "${!TITLES[@]}"; do
        case "${STATUS[i]}" in
            done)    icon="✔" color="$GREEN" ;;
            failed)  icon="✘" color="$RED" ;;
            skipped) icon="↷" color="$YELLOW" ;;
            running) icon="●" color="$FROST" ;;
            *)       icon="○" color="$MUTED" ;;
        esac
        line="$(printf '%-22s' "${TITLES[i]}")"
        printf '  %s%s%s  %s%s%s' "$color" "$icon" "$RESET" "$SNOW" "$line" "$RESET"
        case "${STATUS[i]}" in
            done)    printf '  %s%ss%s\n' "$MUTED" "${DURATION[i]}" "$RESET" ;;
            skipped) printf '  %sskipped%s\n' "$YELLOW" "$RESET" ;;
            failed)  printf '  %sfailed%s\n' "$RED" "$RESET" ;;
            running) printf '  %snow%s\n' "$FROST" "$RESET" ;;
            *)       printf '\n' ;;
        esac
    done
    echo
}

run_step() {
    local i=$1 rc=0 start
    STATUS[i]=running
    render
    printf '  %s── Step %d of %d ─────────────────────────%s\n' "$FROST" $((i + 1)) "${#TITLES[@]}" "$RESET"
    printf '  %s%s%s\n' "$BOLD$SNOW" "${TITLES[i]}" "$RESET"
    printf '  %s%s%s\n\n' "$MUTED" "${TAGLINES[i]}" "$RESET"
    if ! ask; then
        STATUS[i]=skipped
        return 0
    fi
    echo
    start=$SECONDS
    # Run the step in a subshell with errexit, so a failing command stops it.
    set +e
    ( set -e; "${STEP_FUNCS[i]}" )
    rc=$?
    set -e
    DURATION[i]=$((SECONDS - start))
    if (( rc != 0 )); then
        STATUS[i]=failed
        render
        printf '  %s✘ %s failed (exit %d).%s\n' "$RED" "${TITLES[i]}" "$rc" "$RESET"
        printf '  Fix the problem above and run install.sh again. Finished steps can be repeated.\n\n'
        exit "$rc"
    fi
    STATUS[i]=done
}

finish() {
    local i done_count=0 skipped_count=0
    for i in "${!TITLES[@]}"; do
        case "${STATUS[i]}" in
            done)    done_count=$((done_count + 1)) ;;
            skipped) skipped_count=$((skipped_count + 1)) ;;
        esac
    done
    render
    printf '  %sAll set%s  %d installed, %d skipped, %ds total.\n\n' \
        "$GREEN$BOLD" "$RESET" "$done_count" "$skipped_count" "$SECONDS"
    printf '  %sNext%s\n' "$BOLD" "$RESET"
    printf '   %s•%s Log out and back in once, for GNOME settings and keybindings.\n' "$FROST" "$RESET"
    printf '   %s•%s Open bash sessions: %ssource ~/.bashrc && bind -f ~/.inputrc%s\n' "$FROST" "$RESET" "$SNOW" "$RESET"
    printf '   %s•%s Open Kitty windows: Ctrl+Shift+F5 reloads kitty.conf, or reopen them.\n' "$FROST" "$RESET"
    printf '   %s•%s Super+Return opens Kitty. Ctrl+Alt+T does too, once the default terminal step has run.\n\n' "$FROST" "$RESET"
}

main() {
    SECONDS=0
    trap 'printf "\n  %sStopped.%s Run install.sh again to start over. Each step asks first.\n" "$YELLOW" "$RESET"; exit 130' INT
    local i
    clear_screen
    for i in "${!TITLES[@]}"; do
        run_step "$i"
    done
    finish
}

main
