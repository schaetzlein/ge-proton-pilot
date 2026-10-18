#!/usr/bin/env bash
# GE-Proton Manager for native Steam (installed from the Steam website / .deb)
# - Checks GitHub for the newest GE-Proton release
# - Installs it (with checksum verification)
# - Sets it as Steam's default compatibility tool
# - Optionally removes old GE-Proton versions

set -uo pipefail

STEAM_DIR="$HOME/.steam/steam"
COMPAT_DIR="$STEAM_DIR/compatibilitytools.d"
CONFIG_VDF="$STEAM_DIR/config/config.vdf"
API_URL="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"

# ---------- Look & feel ----------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
    GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; CYAN=$'\e[36m'; BLUE=$'\e[34m'
else
    B=""; D=""; R=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; BLUE=""
fi

header() {
    echo
    echo "  ${B}${CYAN}╭──────────────────────────────────────────────╮${R}"
    echo "  ${B}${CYAN}│              GE-Proton Manager               │${R}"
    echo "  ${B}${CYAN}╰──────────────────────────────────────────────╯${R}"
    echo "  ${D}Keeps GE-Proton up to date. GE-Proton is a community${R}"
    echo "  ${D}version of Proton that helps Windows games run on Linux.${R}"
}
section() { echo; echo "  ${B}${BLUE}▌ $1${R}"; echo; }
line()    { echo "    $1"; }
ok()      { echo "    ${GREEN}✔${R} $1"; }
warn()    { echo "    ${YELLOW}!${R} $1"; }
fail()    { echo "    ${RED}✖${R} $1"; }
row()     { printf "    %-24s %s\n" "$1" "$2"; }

box() {  # box "Title" "line 1" "line 2" ...
    local title="$1"; shift
    echo
    echo "    ${YELLOW}┌─ ${B}$title${R}"
    local l
    for l in "$@"; do echo "    ${YELLOW}│${R}  $l"; done
    echo "    ${YELLOW}└──────────────────────────────────────────${R}"
}

finish() {
    echo
    read -rp "  Press ${B}Enter${R} to close this window... " _
    exit "${1:-0}"
}

ask_yes_no() {  # ask_yes_no "Question" [default y|n]
    local default="${2:-n}" hint answer
    [[ "$default" == y ]] && hint="${B}Y${R}/n" || hint="y/${B}N${R}"
    while true; do
        read -rp "  ${B}➜ $1${R} [$hint] " answer
        answer="${answer,,}"
        [[ -z "$answer" ]] && answer="$default"
        case "$answer" in
            y|yes|j|ja) return 0 ;;
            n|no|nein)  return 1 ;;
            *) line "${D}Please type y for yes or n for no, then press Enter.${R}" ;;
        esac
    done
}

ask_choice() {  # ask_choice MAX -> prints the chosen number
    local max="$1" answer
    while true; do
        read -rp "  ${B}➜ Type a number and press Enter:${R} " answer
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= max )); then
            echo "$answer"; return
        fi
        line "${D}Please type a number from 1 to $max.${R}" >&2
    done
}

# ---------- Steam's config.vdf ----------

vdf_tool() {  # vdf_tool get | pinned NAME | set NAME | setall NAME
    # Exit code 3 = Steam has no compatibility setting stored yet
    python3 - "$CONFIG_VDF" "$@" <<'PY'
import sys, re, os

path, mode = sys.argv[1], sys.argv[2]
new_name = sys.argv[3] if len(sys.argv) > 3 else None

try:
    text = open(path, encoding="utf-8").read()
except FileNotFoundError:
    sys.exit(3)

def find_block(text, key, start=0, end=None):
    """Return (open_idx, close_idx) of the { } block that follows "key"."""
    end = len(text) if end is None else end
    m = re.compile(r'"%s"\s*\{' % re.escape(key), re.I).search(text, start, end)
    if not m:
        return None
    i = m.end() - 1
    depth, in_str, j = 0, False, i
    while j < end:
        c = text[j]
        if in_str:
            if c == "\\":
                j += 2
                continue
            if c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return (i, j)
        j += 1
    return None

mapping = find_block(text, "CompatToolMapping")
if mapping is None:
    sys.exit(3)
m_open, m_close = mapping
default = find_block(text, "0", m_open + 1, m_close)
name_re = re.compile(r'("name"\s*")([^"]*)(")', re.I)

if mode == "get":
    if default:
        m = name_re.search(text, default[0], default[1])
        print(m.group(2) if m else "")
    sys.exit(0)

if mode == "pinned":
    # Count games (not the global default) set to a different GE-Proton version
    count = 0
    for m in name_re.finditer(text, m_open, m_close):
        if default and default[0] <= m.start() <= default[1]:
            continue
        if m.group(2).lower().startswith("ge-proton") and m.group(2) != new_name:
            count += 1
    print(count)
    sys.exit(0)

# --- set / setall ---
if mode == "setall":
    block = text[m_open:m_close]
    block = re.sub(r'("name"\s*")(GE-Proton[^"]*)(")',
                   lambda m: m.group(1) + new_name + m.group(3), block, flags=re.I)
    text = text[:m_open] + block + text[m_close:]
    m_close = m_open + len(block)
    default = find_block(text, "0", m_open + 1, m_close)

if default:
    m = name_re.search(text, default[0], default[1])
    if m:
        text = text[:m.start(2)] + new_name + text[m.end(2):]
    else:
        ins = default[0] + 1
        text = text[:ins] + '\n\t\t\t\t\t\t"name"\t\t"%s"' % new_name + text[ins:]
else:
    entry = ('\n\t\t\t\t\t"0"\n\t\t\t\t\t{\n'
             '\t\t\t\t\t\t"name"\t\t"%s"\n'
             '\t\t\t\t\t\t"config"\t\t""\n'
             '\t\t\t\t\t\t"priority"\t\t"75"\n'
             '\t\t\t\t\t}' % new_name)
    text = text[:m_open + 1] + entry + text[m_open + 1:]

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(text)
os.replace(tmp, path)
PY
}

# ---------- Steam process ----------

steam_running() { pgrep -x steam >/dev/null 2>&1; }

close_steam() {
    steam_running || return 0
    echo
    line "Steam has to be closed for a moment so the new setting can be saved."
    line "${D}Running downloads pause and continue when Steam starts again.${R}"
    echo
    ask_yes_no "Close Steam now?" y || return 1
    steam -shutdown >/dev/null 2>&1 &
    printf "    Closing Steam"
    for _ in $(seq 1 60); do
        if ! steam_running; then
            echo " ${GREEN}✔${R}"
            sleep 2
            return 0
        fi
        printf "."
        sleep 1
    done
    echo
    fail "Steam did not close by itself."
    line "Please close Steam (Steam menu → Exit) and run this tool again."
    return 1
}

offer_start_steam() {
    steam_running && return 0
    echo
    if ask_yes_no "Start Steam again?" y; then
        setsid -f steam >/dev/null 2>&1
        ok "Steam is starting."
    fi
}

manual_setup_box() {  # manual_setup_box NAME
    box "One-time setup in Steam" \
        "Steam needs you to pick GE-Proton once yourself." \
        "After that, this tool can switch versions for you." \
        "" \
        "${B}1.${R} Open Steam." \
        "${B}2.${R} Click ${B}Steam${R} (top left) → ${B}Settings${R}." \
        "${B}3.${R} Click ${B}Compatibility${R} on the left." \
        "${B}4.${R} Turn on ${B}Enable Steam Play for all other titles${R}." \
        "${B}5.${R} In the list below it, choose ${B}$1${R}." \
        "${B}6.${R} Click ${B}Restart${R} when Steam asks."
}

# ---------- Actions ----------

installed_versions() {
    [[ -d "$COMPAT_DIR" ]] || return 0
    find "$COMPAT_DIR" -mindepth 1 -maxdepth 1 -type d -name 'GE-Proton*' -printf '%f\n' | sort -V
}

install_version() {  # install_version TAG TARBALL_URL CHECKSUM_URL
    local tag="$1" tar_url="$2" sum_url="$3" tmp
    tmp=$(mktemp -d)
    section "Installing $tag"
    line "Downloading..."
    if ! (cd "$tmp" && curl -fL --progress-bar -O "$tar_url" && curl -fsSL -O "$sum_url"); then
        fail "The download failed. Please check your internet connection and try again."
        rm -rf "$tmp"
        return 1
    fi
    ok "Downloaded"
    if ! (cd "$tmp" && sha512sum -c --status ./*.sha512sum); then
        fail "The download is damaged, so nothing was installed."
        line "Please run this tool again to retry."
        rm -rf "$tmp"
        return 1
    fi
    ok "Checked: the download is complete and genuine"
    mkdir -p "$COMPAT_DIR"
    if ! tar -xf "$tmp"/*.tar.gz -C "$COMPAT_DIR"; then
        fail "Unpacking failed. Is your disk full?"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    ok "Installed ${B}$tag${R}"
}

set_default() {  # set_default NAME
    local name="$1" mode="set" pinned choice
    section "Use $name for your games"

    # Steam has never stored a compatibility choice -> it must be done once by hand
    vdf_tool get >/dev/null 2>&1
    if [[ $? -eq 3 ]]; then
        manual_setup_box "$name"
        offer_start_steam
        return 0
    fi

    pinned=$(vdf_tool pinned "$name" 2>/dev/null || echo 0)
    if [[ "$pinned" =~ ^[0-9]+$ ]] && (( pinned > 0 )); then
        local games="$pinned games" these="those $pinned games"
        (( pinned == 1 )) && games="1 game" && these="that game"
        line "You have ${B}$games${R} set to an older GE-Proton version."
        echo
        line "${B}1)${R} Use $name for all games ${GREEN}(recommended)${R}"
        line "   ${D}${these^} will be switched to it too.${R}"
        line "${B}2)${R} Use $name for all games, but leave $these as before"
        line "${B}3)${R} Don't change anything"
        echo
        choice=$(ask_choice 3)
        case "$choice" in
            1) mode="setall" ;;
            2) mode="set" ;;
            3) line "Okay, nothing was changed."; return 0 ;;
        esac
    else
        ask_yes_no "Should Steam use $name for all games?" y || {
            line "Okay, nothing was changed."
            return 0
        }
    fi

    close_steam || { line "Nothing was changed."; return 1; }

    # Safety copy of Steam's settings (only the 3 newest are kept)
    cp "$CONFIG_VDF" "$CONFIG_VDF.bak-$(date +%Y%m%d-%H%M%S)"
    local backups=() b
    mapfile -t backups < <(printf '%s\n' "$CONFIG_VDF".bak-* | sort -r)
    for b in "${backups[@]:3}"; do rm -f -- "$b"; done

    if vdf_tool "$mode" "$name"; then
        ok "Done! Steam now uses ${B}$name${R} for your games."
    else
        fail "The setting could not be saved. Your Steam settings were not changed."
        manual_setup_box "$name"
    fi
    offer_start_steam
}

remove_old() {  # remove_old KEEP_NAME
    local keep="$1" old=() v size
    mapfile -t old < <(installed_versions | grep -vx "$keep")
    [[ ${#old[@]} -gt 0 ]] || return 0
    size=$(cd "$COMPAT_DIR" && du -sch "${old[@]}" 2>/dev/null | tail -n1 | cut -f1)
    section "Clean up"
    line "These older versions are still on your PC (${B}${size:-?}${R} in total):"
    for v in "${old[@]}"; do line "  • $v"; done
    echo
    line "${D}You only need them if you set a game to one of these versions yourself.${R}"
    echo
    if ask_yes_no "Delete the older versions to free up space?" n; then
        for v in "${old[@]}"; do
            rm -rf "${COMPAT_DIR:?}/$v" && ok "Deleted $v"
        done
        steam_running && warn "Restart Steam so the old versions disappear from its list."
    else
        line "Okay, they stay."
    fi
}

# ---------- Main ----------

header

if [[ ! -d "$STEAM_DIR" ]]; then
    section "Problem"
    fail "Steam was not found on this PC."
    line "This tool works with Steam installed from the Steam website"
    line "or from Linux Mint's package (not the Flatpak version)."
    finish 1
fi
for cmd in curl python3 sha512sum tar; do
    if ! command -v "$cmd" >/dev/null; then
        section "Problem"
        fail "A required program is missing: ${B}$cmd${R}"
        line "Install it by typing this into a terminal:"
        line "  ${B}sudo apt install $cmd${R}"
        finish 1
    fi
done

section "Your current setup"
mapfile -t installed < <(installed_versions)
current_default=$(vdf_tool get 2>/dev/null || true)
if [[ ${#installed[@]} -gt 0 ]]; then
    row "Installed versions:" "${installed[*]}"
else
    row "Installed versions:" "${D}none yet${R}"
fi
if [[ -n "$current_default" && "$current_default" == GE-Proton* ]]; then
    row "Steam is using:" "$current_default"
else
    row "Steam is using:" "${D}Steam's own Proton (not GE-Proton)${R}"
fi

section "Checking for updates"
line "Looking for the newest version online..."
release_json=$(curl -fsSL "$API_URL") || {
    fail "Couldn't reach GitHub. Please check your internet connection and try again."
    finish 1
}
read -r latest tar_url sum_url size_mb < <(python3 -c '
import json, re, sys
arch = sys.argv[1]
d = json.load(sys.stdin)
assets = d.get("assets", [])
urls = [a["browser_download_url"] for a in assets]
is_arm = lambda u: re.search(r"aarch64|arm64", u.rsplit("/", 1)[-1], re.I)
want_arm = arch in ("aarch64", "arm64")
tars = [a for a in assets
        if a["browser_download_url"].endswith(".tar.gz")
        and bool(is_arm(a["browser_download_url"])) == want_arm]
tar = tars[0]["browser_download_url"] if tars else ""
size = round(tars[0].get("size", 0) / 1e6) if tars else 0
# The checksum file has the same name as the archive, ending in .sha512sum
sha = tar[:-len(".tar.gz")] + ".sha512sum" if tar else ""
if sha not in urls:
    sha = ""
# The archive name (e.g. GE-Proton11-9-x86_64) is also the folder it unpacks to
# and the name Steam uses for the tool; it can differ from the release tag
name = tar.rsplit("/", 1)[-1][:-len(".tar.gz")] if tar and d.get("tag_name") else ""
print(name, tar, sha, size)
' "$(uname -m)" <<<"$release_json")

if [[ -z "${latest:-}" || -z "${tar_url:-}" || -z "${sum_url:-}" ]]; then
    fail "The update information from GitHub couldn't be read."
    line "Please try again later."
    finish 1
fi
row "Newest version:" "${B}$latest${R}"
echo

if printf '%s\n' "${installed[@]}" | grep -qx "$latest"; then
    if [[ "$current_default" == "$latest" ]]; then
        ok "${GREEN}Everything is up to date.${R} Nothing to do."
    else
        ok "The newest version is already installed."
        warn "But Steam isn't using it yet."
        set_default "$latest"
    fi
else
    ok "${GREEN}A new version is available!${R}"
    echo
    if ask_yes_no "Download and install $latest now? (about ${size_mb:-?} MB)" y; then
        if install_version "$latest" "$tar_url" "$sum_url"; then
            set_default "$latest"
        else
            finish 1
        fi
    else
        line "Okay, nothing was installed."
    fi
fi

if installed_versions | grep -qx "$latest"; then
    remove_old "$latest"
fi

section "All done"
finish 0
