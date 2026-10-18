#!/usr/bin/env bash
# GE-Proton Pilot for Steam on Linux (native .deb, Flatpak or Snap)
# - Checks GitHub for the newest GE-Proton release
# - Installs it (with checksum verification)
# - Sets it as Steam's default compatibility tool
# - Optionally removes old GE-Proton versions
# Asks before every step; see --help for --check and --auto.
#
# GE-Proton itself is made by GloriousEggroll and contributors:
# https://github.com/GloriousEggroll/proton-ge-custom

set -uo pipefail

# Where each kind of Steam keeps its files (set by choose_steam)
STEAM_KINDS=(native flatpak snap)
declare -A STEAM_PATHS=(
    [native]="$HOME/.steam/steam"
    [flatpak]="$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    [snap]="$HOME/snap/steam/common/.steam/steam"
)
declare -A STEAM_LABELS=([native]="Steam (standard install)" [flatpak]="Steam (Flatpak)" [snap]="Steam (Snap)")
STEAM_KIND="" STEAM_DIR="" COMPAT_DIR="" CONFIG_VDF="" STEAM_CMD=()
API_URL="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
case "$(uname -m)" in aarch64|arm64) HOST_ARCH=arm ;; *) HOST_ARCH=x86 ;; esac

# ---------- Look & feel ----------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
    GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; CYAN=$'\e[36m'; BLUE=$'\e[34m'
else
    B=""; D=""; R=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; BLUE=""
fi

header() {
    echo "  ${B}${CYAN}╭──────────────────────────────────────────────╮${R}"
    echo "  ${B}${CYAN}│               GE-Proton Pilot                │${R}"
    echo "  ${B}${CYAN}╰──────────────────────────────────────────────╯${R}"
    echo "  ${D}Keeps GE-Proton, a community Proton for Windows games, up to date.${R}"
    echo "  ${D}GE-Proton is made by GloriousEggroll – thank you!${R}"
    echo "  ${D}https://github.com/GloriousEggroll/proton-ge-custom${R}"
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

finish() {  # finish [EXIT_CODE] -> in interactive mode, wait so a double-clicked window stays open
    if [[ "${MODE:-interactive}" == interactive ]]; then
        local done=""
        [[ "${1:-0}" == 0 ]] && done="${B}${GREEN}All done.${R} "
        echo
        read -rp "  ${done}Press ${B}Enter${R} to close this window... " _
    fi
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

vdf_tool() {  # vdf_tool get | used | pinned NAME | otherseries NAME | set NAME | setall NAME | moveseries NAME
    # A series is the number after GE-Proton (GE-Proton10-34 -> 10)
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

def series(name):
    m = re.match(r"GE-Proton(\d+)-", name or "", re.I)
    return m.group(1) if m else None

def older_in_series(name):
    """True for a different build of the same series as new_name."""
    return name != new_name and series(name) is not None and series(name) == series(new_name)

if mode == "get":
    if default:
        m = name_re.search(text, default[0], default[1])
        print(m.group(2) if m else "")
    sys.exit(0)

if mode == "used":
    # Every tool Steam is set to use, the default included
    for m in name_re.finditer(text, m_open, m_close):
        print(m.group(2))
    sys.exit(0)

if mode == "pinned":
    # Count games (not the global default) set to another build of the same series
    count = 0
    for m in name_re.finditer(text, m_open, m_close):
        if default and default[0] <= m.start() <= default[1]:
            continue
        if older_in_series(m.group(2)):
            count += 1
    print(count)
    sys.exit(0)

if mode == "otherseries":
    # "COUNT NAME" for each GE-Proton build of another series that games are set to
    counts = {}
    for m in name_re.finditer(text, m_open, m_close):
        if default and default[0] <= m.start() <= default[1]:
            continue
        if series(m.group(2)) not in (None, series(new_name)):
            counts[m.group(2)] = counts.get(m.group(2), 0) + 1
    for name, count in sorted(counts.items()):
        print(count, name)
    sys.exit(0)

# --- set / setall / moveseries ---
if mode in ("setall", "moveseries"):
    # Switch everything on another build of the same series; other series stay as they are
    block = text[m_open:m_close]
    block = name_re.sub(lambda m: m.group(1) + (new_name if older_in_series(m.group(2)) else m.group(2))
                        + m.group(3), block)
    text = text[:m_open] + block + text[m_close:]
    m_close = m_open + len(block)
    default = find_block(text, "0", m_open + 1, m_close)

# moveseries leaves the default alone unless it was on the same series
if mode != "moveseries" and default:
    m = name_re.search(text, default[0], default[1])
    if m:
        text = text[:m.start(2)] + new_name + text[m.end(2):]
    else:
        ins = default[0] + 1
        text = text[:ins] + '\n\t\t\t\t\t\t"name"\t\t"%s"' % new_name + text[ins:]
elif mode != "moveseries":
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

choose_steam() {  # sets STEAM_KIND, STEAM_DIR, ... ; returns 1 if no Steam, 2 if a choice is needed
    local found=() k i choice path
    for k in "${STEAM_KINDS[@]}"; do
        [[ -n "$STEAM_CHOICE" && "$k" != "$STEAM_CHOICE" ]] && continue
        [[ -d "${STEAM_PATHS[$k]}" ]] && found+=("$k")
    done
    case ${#found[@]} in
        0) return 1 ;;
        1) STEAM_KIND="${found[0]}" ;;
        *)
            [[ "$MODE" != interactive ]] && return 2
            section "Which Steam?"
            line "More than one Steam is installed on this PC:"
            echo
            for i in "${!found[@]}"; do
                path="${STEAM_PATHS[${found[$i]}]}"
                line "${B}$(( i + 1 )))${R} ${STEAM_LABELS[${found[$i]}]}  ${D}~${path#"$HOME"}${R}"
            done
            echo
            choice=$(ask_choice ${#found[@]})
            STEAM_KIND="${found[$(( choice - 1 ))]}"
            ;;
    esac
    STEAM_DIR="${STEAM_PATHS[$STEAM_KIND]}"
    COMPAT_DIR="$STEAM_DIR/compatibilitytools.d"
    CONFIG_VDF="$STEAM_DIR/config/config.vdf"
    case "$STEAM_KIND" in
        flatpak) STEAM_CMD=(flatpak run com.valvesoftware.Steam) ;;
        snap)    STEAM_CMD=(snap run steam) ;;
        *)       STEAM_CMD=(steam) ;;
    esac
}

steam_running() { pgrep -x steam >/dev/null 2>&1; }

close_steam() {
    steam_running || return 0
    echo
    line "Steam has to be closed for a moment so the new setting can be saved."
    line "${D}Running downloads pause and continue when Steam starts again.${R}"
    echo
    ask_yes_no "Close Steam now?" y || return 1
    "${STEAM_CMD[@]}" -shutdown >/dev/null 2>&1 &
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
        setsid -f "${STEAM_CMD[@]}" >/dev/null 2>&1
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

contains() {  # contains NEEDLE ITEM... -> success if NEEDLE is one of the items
    local needle="$1" item; shift
    for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
    return 1
}

wrong_arch() {  # wrong_arch NAME -> success if this build can't run on this PC
    # Builds without an aarch64/arm64 suffix are x86_64 (older releases had no suffix)
    local build=x86
    [[ "${1,,}" =~ aarch64|arm64 ]] && build=arm
    [[ "$build" != "$HOST_ARCH" ]]
}

series_of() {  # series_of NAME -> the series number (GE-Proton10-34 -> 10), empty if none
    [[ "$1" =~ ^GE-Proton([0-9]+)- ]] && echo "${BASH_REMATCH[1]}"
}

installed_versions() {
    [[ -d "$COMPAT_DIR" ]] || return 0
    find "$COMPAT_DIR" -mindepth 1 -maxdepth 1 -type d -name 'GE-Proton*' -printf '%f\n' | sort -V
}

progress_bar() {  # progress_bar DONE_BYTES TOTAL_BYTES (TOTAL 0 = unknown)
    local have="$1" total="$2" width=30 pct filled bar rest
    if (( total > 0 )); then
        pct=$(( have * 100 / total )); (( pct > 100 )) && pct=100
        filled=$(( pct * width / 100 ))
        printf -v bar '%*s' "$filled" ''
        printf -v rest '%*s' $(( width - filled )) ''
        printf '\r    %s%s%s%s%s %3d%%  %d / %d MB ' "$GREEN" "${bar// /█}" "$D" "${rest// /░}" "$R" \
            "$pct" $(( have / 1000000 )) $(( total / 1000000 ))
    else
        printf '\r    %d MB downloaded ' $(( have / 1000000 ))
    fi
}

download() {  # download URL FILE [TOTAL_BYTES] -> shows an indented progress bar on a terminal
    local url="$1" file="$2" total="${3:-0}" pid status
    curl -fsSL -o "$file" "$url" &
    pid=$!
    if [[ -t 1 ]]; then
        while kill -0 "$pid" 2>/dev/null; do
            progress_bar "$(stat -c %s "$file" 2>/dev/null || echo 0)" "$total"
            sleep 0.5
        done
    fi
    wait "$pid"; status=$?
    if [[ -t 1 ]]; then
        (( status == 0 )) && progress_bar "$(stat -c %s "$file" 2>/dev/null || echo 0)" "$total"
        echo
    fi
    return "$status"
}

install_version() {  # install_version TAG TARBALL_URL CHECKSUM_URL [TARBALL_BYTES]
    local tag="$1" tar_url="$2" sum_url="$3" bytes="${4:-0}" tmp
    tmp=$(mktemp -d)
    section "Installing $tag"
    line "Downloading..."
    if ! download "$tar_url" "$tmp/${tar_url##*/}" "$bytes" ||
       ! curl -fsSL -o "$tmp/${sum_url##*/}" "$sum_url"; then
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

backup_config() {  # safety copy of Steam's settings (only the 3 newest are kept)
    local backups=() b
    if ! cp "$CONFIG_VDF" "$CONFIG_VDF.bak-$(date +%Y%m%d-%H%M%S)"; then
        fail "Couldn't make a safety copy of Steam's settings, so nothing was changed."
        line "Is your disk full?"
        return 1
    fi
    mapfile -t backups < <(printf '%s\n' "$CONFIG_VDF".bak-* | sort -r)
    for b in "${backups[@]:3}"; do rm -f -- "$b"; done
}

set_default() {  # set_default NAME
    local name="$1" mode="set" pinned choice series
    series=$(series_of "$name")
    section "Make $name the default"

    # Steam has never stored a compatibility choice -> it must be done once by hand
    vdf_tool get >/dev/null 2>&1
    if [[ $? -eq 3 ]]; then
        manual_setup_box "$name"
        offer_start_steam
        return 0
    fi

    pinned=$(vdf_tool pinned "$name" 2>/dev/null || echo 0)
    [[ "$pinned" =~ ^[0-9]+$ ]] || pinned=0
    local games="$pinned games" these="those $pinned games"
    (( pinned == 1 )) && games="1 game" && these="that game"
    line "${D}Steam uses the default for every game you haven't set to a version yourself.${R}"
    echo
    (( pinned > 0 )) && line "You have ${B}$games${R} set to an older GE-Proton$series version."
    # Games on another series were set to it on purpose, so they are only mentioned
    local count other
    while read -r count other; do
        if (( count == 1 )); then
            line "1 game is set to ${B}$other${R} and stays on it."
        else
            line "$count games are set to ${B}$other${R} and stay on it."
        fi
    done < <(vdf_tool otherseries "$name" 2>/dev/null)
    if (( pinned > 0 )); then
        echo
        line "${B}1)${R} Use $name as the default, and for $these too ${GREEN}(recommended)${R}"
        line "${B}2)${R} Use $name as the default, but leave $these as before"
        line "${B}3)${R} Don't change anything"
        echo
        choice=$(ask_choice 3)
        case "$choice" in
            1) mode="setall" ;;
            2) mode="set" ;;
            3) line "Okay, nothing was changed."; return 0 ;;
        esac
    else
        ask_yes_no "Should Steam use $name as the default?" y || {
            line "Okay, nothing was changed."
            return 0
        }
    fi

    close_steam || { line "Nothing was changed."; return 1; }

    backup_config || { offer_start_steam; return 1; }

    if vdf_tool "$mode" "$name"; then
        ok "Done! Steam now uses ${B}$name${R} as the default."
    else
        fail "The setting could not be saved. Your Steam settings were not changed."
        manual_setup_box "$name"
    fi
    offer_start_steam
}

switch_series() {  # switch_series NAME -> offer to move games on older builds of NAME's series to it
    local name="$1" series current pinned default_too=0
    (( has_mapping )) || return 0
    series=$(series_of "$name")
    pinned=$(vdf_tool pinned "$name" 2>/dev/null || echo 0)
    [[ "$pinned" =~ ^[0-9]+$ ]] || pinned=0
    current=$(vdf_tool get 2>/dev/null)
    [[ "$current" != "$name" && "$(series_of "$current")" == "$series" ]] && default_too=1
    (( pinned + default_too > 0 )) || return 0
    echo
    if (( pinned > 0 )); then
        local games="$pinned games"
        (( pinned == 1 )) && games="1 game"
        line "You have ${B}$games${R} set to an older GE-Proton$series version."
    fi
    (( default_too )) && line "Steam's default is ${B}$current${R}."
    ask_yes_no "Switch them to $name?" y || { line "Okay, they stay as they are."; return 0; }
    close_steam || { line "Nothing was changed."; return 1; }
    backup_config || { offer_start_steam; return 1; }
    if vdf_tool moveseries "$name"; then
        ok "Done! They now use ${B}$name${R}."
    else
        fail "The setting could not be saved. Your Steam settings were not changed."
    fi
    offer_start_steam
}

update_older_series() {  # update_older_series MAIN_SERIES -> offer each other installed series' last build
    local main="$1" v s name seen=()
    declare -A newest=()
    for v in "${usable[@]}"; do
        s=$(series_of "$v")
        [[ -z "$s" || "$s" == "$main" ]] && continue
        contains "$s" "${seen[@]}" || seen+=("$s")
        newest[$s]="$v"  # installed_versions is sorted, so the last one is the newest
    done
    for s in "${seen[@]}"; do
        fetch_version "$s"
        name="$latest"
        [[ "$name" == "${newest[$s]}" ]] && continue
        section "Update GE-Proton$s"
        line "You have ${B}${newest[$s]}${R}. The newest GE-Proton$s is ${B}$name${R}."
        echo
        if ask_yes_no "Download and install $name now? (about ${size_mb:-?} MB)" y; then
            install_version "$name" "$tar_url" "$sum_url" "${size_bytes:-0}" && switch_series "$name"
        else
            line "Okay, nothing was installed."
        fi
    done
}

remove_old() {  # offer to delete builds nothing needs: older builds of a series and wrong-type builds
    local all=() used=() old=() kept=() v s size any_wrong=0 all_wrong=1 default=n
    declare -A newest=()
    mapfile -t all < <(installed_versions)
    for v in "${all[@]}"; do
        wrong_arch "$v" && continue
        s=$(series_of "$v")
        newest[x$s]="$v"  # installed_versions is sorted, so the last one is the newest
    done
    mapfile -t used < <(vdf_tool used 2>/dev/null)
    for v in "${all[@]}"; do
        if ! wrong_arch "$v"; then
            s=$(series_of "$v")
            [[ "${newest[x$s]}" == "$v" ]] && continue
        fi
        if contains "$v" "${used[@]}"; then
            kept+=("$v")
            continue
        fi
        if wrong_arch "$v"; then
            any_wrong=1
        else
            all_wrong=0
        fi
        old+=("$v")
    done
    [[ ${#old[@]} -gt 0 ]] || return 0
    size=$(cd "$COMPAT_DIR" && du -sch "${old[@]}" 2>/dev/null | tail -n1 | cut -f1)
    section "Clean up"
    line "These older versions are still on your PC (${B}${size:-?}${R} in total):"
    for v in "${old[@]}"; do
        if wrong_arch "$v"; then
            line "  • $v ${YELLOW}(wrong type for this PC)${R}"
        else
            line "  • $v"
        fi
    done
    echo
    (( any_wrong )) && line "${D}Versions of the wrong type can't run on this PC at all.${R}"
    if (( all_wrong )); then
        default=y  # nothing in the list can ever be used here
    else
        line "${D}No game uses them, and a newer build of the same series is installed.${R}"
    fi
    (( ${#kept[@]} )) && line "${D}Kept because Steam is set to use them: ${kept[*]}${R}"
    echo
    if ask_yes_no "Delete the older versions to free up space?" "$default"; then
        for v in "${old[@]}"; do
            rm -rf "${COMPAT_DIR:?}/$v" && ok "Deleted $v"
        done
        steam_running && warn "Restart Steam so the old versions disappear from its list."
    else
        line "Okay, they stay."
    fi
}

# ---------- Main ----------

usage() {
    cat <<EOF
GE-Proton Pilot - keeps GE-Proton up to date for Steam on Linux.

Usage: ${0##*/} [OPTION]

Without options, the tool asks before every step.

Options:
  --check          Only check for an update. Exit code 0 = nothing to do,
                   10 = an update is available (or installed but not used yet).
  --auto           Install the newest version and make it Steam's default
                   without asking. Steam must be closed. Games set to a
                   specific version and old versions are left alone.
  --install VERSION
                   Install one specific version without changing Steam's
                   default, e.g. for a game that needs an older one.
                   VERSION is a series like 10 (its newest release) or an
                   exact version like GE-Proton10-34. Old series such as
                   9 and 10 are finished and get no more updates.
  --steam KIND     Which Steam to use if more than one is installed:
                   native, flatpak or snap.
  -h, --help       Show this help.

Exit codes: 0 ok, 1 error, 2 wrong usage, 3 Steam is running (--auto),
10 update available (--check).
EOF
}

check_requirements() {
    local cmd status
    for cmd in curl python3 sha512sum tar; do
        if ! command -v "$cmd" >/dev/null; then
            section "Problem"
            fail "A required program is missing: ${B}$cmd${R}"
            line "Install it by typing this into a terminal:"
            line "  ${B}sudo apt install $cmd${R}"
            finish 1
        fi
    done
    choose_steam; status=$?
    case $status in
        0) ;;
        2)
            fail "More than one Steam is installed. Choose one with ${B}--steam native${R}, ${B}--steam flatpak${R} or ${B}--steam snap${R}."
            finish 2 ;;
        *)
            section "Problem"
            if [[ -n "$STEAM_CHOICE" ]]; then
                fail "No ${STEAM_LABELS[$STEAM_CHOICE]} was found on this PC."
            else
                fail "Steam was not found on this PC."
                line "This tool works with Steam installed from the Steam website,"
                line "your Linux package manager, Flatpak or Snap."
                line "Please start Steam once, then run this tool again."
            fi
            finish 1 ;;
    esac
}

scan_installed() {  # sets installed, usable, current_default, default_wrong, has_mapping
    local v
    mapfile -t installed < <(installed_versions)
    usable=()
    for v in "${installed[@]}"; do wrong_arch "$v" || usable+=("$v"); done
    has_mapping=1
    current_default=$(vdf_tool get 2>/dev/null) || { [[ $? -eq 3 ]] && has_mapping=0; }
    default_wrong=0
    [[ "$current_default" == GE-Proton* ]] && wrong_arch "$current_default" && default_wrong=1
    return 0
}

api_get() {  # api_get URL -> sets API_BODY; returns 1 if GitHub has nothing there (404)
    local status remaining reset tmp
    tmp=$(mktemp -d)
    if ! status=$(curl -sSL -D "$tmp/headers" -o "$tmp/body" -w '%{http_code}' "$1" 2>/dev/null); then
        rm -rf "$tmp"
        fail "Couldn't reach GitHub. Please check your internet connection and try again."
        finish 1
    fi
    API_BODY=$(<"$tmp/body")
    # With redirects there can be several header blocks; the last one counts
    remaining=$(grep -i '^x-ratelimit-remaining:' "$tmp/headers" | tail -n1 | tr -dc '0-9')
    reset=$(grep -i '^x-ratelimit-reset:' "$tmp/headers" | tail -n1 | tr -dc '0-9')
    rm -rf "$tmp"
    [[ "$status" == 200 ]] && return 0
    [[ "$status" == 404 ]] && return 1
    if [[ "$status" == 429 || ( "$status" == 403 && "$remaining" == 0 ) ]]; then
        fail "GitHub is getting too many update checks from your internet connection."
        if [[ -n "$reset" ]] && reset=$(date -d "@$reset" +%H:%M 2>/dev/null); then
            line "This is a temporary limit. Please try again after ${B}$reset${R}."
        else
            line "This is a temporary limit. Please try again in an hour."
        fi
    else
        fail "GitHub answered with an error (code $status)."
        line "This is usually temporary. Please try again later."
    fi
    finish 1
}

parse_release() {  # parse_release [MAJOR] < JSON -> prints "NAME TAR_URL SUM_URL SIZE_MB SIZE_BYTES"
    # Reads one release, or with MAJOR a list of releases and picks the newest of that series.
    # Exit code 2 = the list is empty, 3 = no such series in the list, 4 = no build for this PC
    python3 -c '
import json, re, sys
arch, major = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin)
if major:
    if not d:
        sys.exit(2)
    series = [(int(m.group(1)), r) for r in d
              for m in [re.fullmatch(r"GE-Proton%s-(\d+)" % major, r.get("tag_name", ""))] if m]
    if not series:
        sys.exit(3)
    d = max(series, key=lambda s: s[0])[1]
assets = d.get("assets", [])
urls = [a["browser_download_url"] for a in assets]
is_arm = lambda u: re.search(r"aarch64|arm64", u.rsplit("/", 1)[-1], re.I)
want_arm = arch in ("aarch64", "arm64")
tars = [a for a in assets
        if a["browser_download_url"].endswith(".tar.gz")
        and bool(is_arm(a["browser_download_url"])) == want_arm]
if d.get("tag_name") and assets and not tars:
    sys.exit(4)
tar = tars[0]["browser_download_url"] if tars else ""
size_bytes = tars[0].get("size", 0) if tars else 0
size = round(size_bytes / 1e6)
# The checksum file has the same name as the archive, ending in .sha512sum
sha = tar[:-len(".tar.gz")] + ".sha512sum" if tar else ""
if sha not in urls:
    sha = ""
# The archive name (e.g. GE-Proton11-9-x86_64) is also the folder it unpacks to
# and the name Steam uses for the tool; it can differ from the release tag
name = tar.rsplit("/", 1)[-1][:-len(".tar.gz")] if tar and d.get("tag_name") else ""
print(name, tar, sha, size, size_bytes)
' "$(uname -m)" "${1:-}"
}

unreadable_release() {
    fail "The update information from GitHub couldn't be read."
    line "Please try again later."
    finish 1
}

fetch_release() {  # sets latest, tar_url, sum_url, size_mb, size_bytes
    api_get "$API_URL" || unreadable_release
    read -r latest tar_url sum_url size_mb size_bytes < <(parse_release <<<"$API_BODY")
    if [[ -z "${latest:-}" || -z "${tar_url:-}" || -z "${sum_url:-}" ]]; then
        unreadable_release
    fi
}

fetch_version() {  # fetch_version VERSION (e.g. 10 or GE-Proton10-34) -> like fetch_release
    local version="$1" major="" page info status
    if [[ "$version" =~ ^[0-9]+$ ]]; then
        # Newest release of that series; the list is sorted newest first
        major="$version"
        for page in 1 2 3 4 5; do
            api_get "${API_URL%/latest}?per_page=100&page=$page" || unreadable_release
            info=$(parse_release "$major" <<<"$API_BODY"); status=$?
            (( status == 3 )) && continue
            break
        done
        version="GE-Proton$major"
    else
        if api_get "${API_URL%/latest}/tags/$version"; then
            info=$(parse_release <<<"$API_BODY"); status=$?
        else
            status=3
        fi
    fi
    case $status in
        0) ;;
        2|3)
            fail "GitHub has no GE-Proton release called ${B}$version${R}."
            line "Check the name on ${B}github.com/GloriousEggroll/proton-ge-custom/releases${R}."
            finish 1 ;;
        4)
            fail "${B}$version${R} has no build for this type of PC."
            finish 1 ;;
        *) unreadable_release ;;
    esac
    read -r latest tar_url sum_url size_mb size_bytes <<<"$info"
    if [[ -z "${latest:-}" || -z "${tar_url:-}" || -z "${sum_url:-}" ]]; then
        unreadable_release
    fi
}

run_check() {
    scan_installed
    fetch_release
    if ! contains "$latest" "${usable[@]}"; then
        echo "Update available: $latest"
        exit 10
    elif [[ "$current_default" != "$latest" ]] && (( has_mapping )); then
        echo "$latest is installed, but Steam isn't using it yet."
        exit 10
    fi
    echo "Up to date: $latest"
    exit 0
}

run_auto() {
    if steam_running; then
        fail "Steam is running. Please close Steam and run this again. Nothing was changed."
        exit 3
    fi
    scan_installed
    fetch_release
    if ! contains "$latest" "${usable[@]}"; then
        install_version "$latest" "$tar_url" "$sum_url" "${size_bytes:-0}" || exit 1
    fi
    if [[ "$current_default" == "$latest" ]]; then
        ok "Up to date: Steam already uses ${B}$latest${R}."
        exit 0
    fi
    if (( ! has_mapping )); then
        fail "$latest is installed, but Steam has to be set up once by hand first."
        manual_setup_box "$latest"
        exit 1
    fi
    backup_config || exit 1
    if vdf_tool set "$latest"; then
        ok "Steam now uses ${B}$latest${R} as the default."
    else
        fail "The setting could not be saved. Your Steam settings were not changed."
        exit 1
    fi
}

run_install() {  # install one specific version, e.g. an older series for a single game
    scan_installed
    fetch_version "$INSTALL_VERSION"
    if contains "$latest" "${usable[@]}"; then
        ok "${B}$latest${R} is already installed."
    else
        install_version "$latest" "$tar_url" "$sum_url" "${size_bytes:-0}" || exit 1
        steam_running && warn "Restart Steam so $latest shows up in its list."
    fi
    line "Steam's default was not changed. To use $latest for one game:"
    line "  ${B}1.${R} In your Steam library, right-click the game → ${B}Properties${R}."
    line "  ${B}2.${R} Click ${B}Compatibility${R} and turn on ${B}Force the use of a specific${R}"
    line "     ${B}Steam Play compatibility tool${R}."
    line "  ${B}3.${R} Choose ${B}$latest${R} in the list."
    exit 0
}

run_interactive() {
    local v label offered_default=0

    header
    check_requirements

    section "Your current setup"
    row "Steam:" "${STEAM_LABELS[$STEAM_KIND]}"
    scan_installed
    if [[ ${#installed[@]} -gt 0 ]]; then
        label="Installed versions:"
        for v in "${installed[@]}"; do
            if wrong_arch "$v"; then
                row "$label" "$v ${YELLOW}(wrong type for this PC)${R}"
            else
                row "$label" "$v"
            fi
            label=""
        done
    else
        row "Installed versions:" "${D}none yet${R}"
    fi
    if (( default_wrong )); then
        row "Steam is using:" "$current_default ${YELLOW}(wrong type for this PC)${R}"
    elif [[ -n "$current_default" && "$current_default" == GE-Proton* ]]; then
        row "Steam is using:" "$current_default"
    else
        row "Steam is using:" "${D}Steam's own Proton (not GE-Proton)${R}"
    fi
    if (( default_wrong )); then
        box "Steam is set to the wrong type of GE-Proton" \
            "${B}$current_default${R} is made for a different kind of PC," \
            "so games that use it won't start." \
            "This tool will offer to fix that below."
    fi

    section "Checking for updates"
    line "Looking for the newest version online..."
    fetch_release
    row "Newest version:" "${B}$latest${R}"
    echo

    if contains "$latest" "${usable[@]}"; then
        if [[ "$current_default" == "$latest" ]]; then
            ok "${GREEN}Everything is up to date.${R} Nothing to do."
        else
            ok "The newest version is already installed."
            warn "But Steam isn't using it yet."
            offered_default=1
            set_default "$latest"
        fi
    else
        ok "${GREEN}A new version is available!${R}"
        echo
        if ask_yes_no "Download and install $latest now? (about ${size_mb:-?} MB)" y; then
            if install_version "$latest" "$tar_url" "$sum_url" "${size_bytes:-0}"; then
                offered_default=1
                set_default "$latest"
            else
                finish 1
            fi
        else
            line "Okay, nothing was installed."
        fi
    fi

    # Steam still points to a build that can't run here and we haven't offered a fix yet
    if (( default_wrong && ! offered_default )); then
        scan_installed
        if [[ ${#usable[@]} -gt 0 ]]; then
            set_default "${usable[-1]}"
        else
            warn "Steam is still set to ${B}$current_default${R}, which can't run on this PC."
            line "Install the newest version to fix this."
        fi
    fi

    scan_installed
    update_older_series "$(series_of "$latest")"
    remove_old

    finish 0
}

MODE=interactive STEAM_CHOICE="" INSTALL_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)   MODE=check ;;
        --auto)    MODE=auto ;;
        --install) MODE=install INSTALL_VERSION="${2:-}"; shift ;;
        --install=*) MODE=install INSTALL_VERSION="${1#*=}" ;;
        --steam)   STEAM_CHOICE="${2:-}"; shift ;;
        --steam=*) STEAM_CHOICE="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    esac
    shift
done
if [[ -n "$STEAM_CHOICE" && -z "${STEAM_PATHS[$STEAM_CHOICE]+set}" ]]; then
    echo "--steam must be native, flatpak or snap (not \"$STEAM_CHOICE\")." >&2
    exit 2
fi
if [[ "$MODE" == install && ! "$INSTALL_VERSION" =~ ^([0-9]+|GE-Proton[0-9]+-[0-9]+)$ ]]; then
    echo "--install needs a series like 10 or a version like GE-Proton10-34 (not \"$INSTALL_VERSION\")." >&2
    exit 2
fi

case "$MODE" in
    check) check_requirements; run_check ;;
    auto)  check_requirements; run_auto ;;
    install) check_requirements; run_install ;;
    *)     run_interactive ;;
esac
