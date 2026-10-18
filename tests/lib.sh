# Shared helpers for the tests: build a fake HOME, Steam folder and GitHub release.
# shellcheck shell=bash

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TESTS_DIR/../ge-proton-pilot.sh"

setup_env() {  # setup_env -> fresh fake HOME, Steam dir and server in $WORK
    WORK=$(mktemp -d)
    export HOME="$WORK/home" FAKE_SERVER="$WORK/server" FAKE_STEAM_RUNNING="$WORK/steam.running"
    export PATH="$TESTS_DIR/fakebin:$PATH" NO_COLOR=1 FAKE_ARCH=x86_64 FAKE_CURL_DELAY=0
    STEAM="$HOME/.steam/steam"
    mkdir -p "$STEAM/config" "$STEAM/compatibilitytools.d" "$FAKE_SERVER"
}

add_installed() {  # add_installed NAME... -> fake GE-Proton folders
    local n
    for n in "$@"; do
        mkdir -p "$STEAM/compatibilitytools.d/$n"
        echo "\"compatibilitytools\" { \"compat_tools\" { \"$n\" { \"display_name\" \"$n\" } } }" \
            > "$STEAM/compatibilitytools.d/$n/compatibilitytool.vdf"
    done
}

write_config() {  # write_config DEFAULT [GAMEID=NAME...] -> config.vdf with a CompatToolMapping
    local default="$1" g; shift
    {
        printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
        printf '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n'
        printf '\t\t\t\t\t"0"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"75"\n\t\t\t\t\t}\n' "$default"
        for g in "$@"; do
            printf '\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' "${g%%=*}" "${g#*=}"
        done
        printf '\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n'
    } > "$STEAM/config/config.vdf"
}

write_config_without_mapping() {  # Steam never stored a compatibility choice
    printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t}\n\t\t}\n\t}\n}\n' \
        > "$STEAM/config/config.vdf"
}

build_assets() {  # build_assets NAME... -> archive + checksum per build on the fake server
    local name build="$WORK/build"
    for name in "$@"; do
        mkdir -p "$build/$name"
        echo "\"compatibilitytools\" { \"compat_tools\" { \"$name\" { \"display_name\" \"$name\" } } }" \
            > "$build/$name/compatibilitytool.vdf"
        head -c $(( ${FILLER_MB:-1} * 1000000 )) /dev/urandom > "$build/$name/filler"
        tar -czf "$FAKE_SERVER/$name.tar.gz" -C "$build" "$name"
        (cd "$FAKE_SERVER" && sha512sum "$name.tar.gz" > "$name.sha512sum")
    done
}

release_json() {  # release_json TAG NAME... -> a release on the fake server (tags/TAG.json + releases.json)
    local tag="$1"; shift
    mkdir -p "$FAKE_SERVER/tags"
    python3 -I - "$tag" "$FAKE_SERVER" "$@" <<'PY2'
import json, os, sys
tag, srv, names = sys.argv[1], sys.argv[2], sys.argv[3:]
base = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/" + tag + "/"
assets = [{"name": f, "browser_download_url": base + f, "size": os.path.getsize(os.path.join(srv, f))}
          for n in names for f in (n + ".sha512sum", n + ".tar.gz")]
release = {"tag_name": tag, "assets": assets}
json.dump(release, open(os.path.join(srv, "tags", tag + ".json"), "w"))
# The list is newest first, like GitHub's
path = os.path.join(srv, "releases.json")
releases = json.load(open(path)) if os.path.exists(path) else []
json.dump([release] + releases, open(path, "w"))
PY2
}

publish_release() {  # publish_release TAG -> x86_64 + aarch64 assets; becomes the latest release
    build_assets "$1-x86_64" "$1-aarch64"
    release_json "$1" "$1-aarch64" "$1-x86_64"
    cp "$FAKE_SERVER/tags/$1.json" "$FAKE_SERVER/release.json"
}

publish_old_release() {  # publish_old_release TAG -> one unsuffixed x86_64 build, like GE-Proton9/10
    build_assets "$1"
    release_json "$1" "$1"
}

vdf_names() {  # print every "name" value in config.vdf, one per line
    grep -oP '"name"\s*"\K[^"]*' "$STEAM/config/config.vdf"
}

run_script() {  # run_script ANSWERS [ARGS...] -> sets OUTPUT and STATUS; ANSWERS are typed lines
    local answers="$1"; shift
    OUTPUT=$(printf '%b' "$answers" | bash "$SCRIPT" "$@" 2>&1)
    STATUS=$?
}

compat_names() {  # print the "name" of a CompatToolMapping entry: compat_names GAMEID
    python3 -I - "$STEAM/config/config.vdf" "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'"%s"\s*\{[^}]*?"name"\s*"([^"]*)"' % re.escape(sys.argv[2]), text)
print(m.group(1) if m else "")
PY
}

# ---------- Assertions (each prints why it failed and returns 1) ----------

fail_test() { echo "      FAIL: $*"; return 1; }
assert_status()       { [[ "$STATUS" == "$1" ]] || fail_test "exit code $STATUS, expected $1"; }
assert_output()       { [[ "$OUTPUT" == *"$1"* ]] || fail_test "output lacks: $1"; }
assert_no_output()    { [[ "$OUTPUT" != *"$1"* ]] || fail_test "output should not contain: $1"; }
assert_installed()    { [[ -d "$STEAM/compatibilitytools.d/$1" ]] || fail_test "$1 is not installed"; }
assert_not_installed() { [[ ! -e "$STEAM/compatibilitytools.d/$1" ]] || fail_test "$1 should not be installed"; }
assert_mapping()      { local got; got=$(compat_names "$1"); [[ "$got" == "$2" ]] || fail_test "entry \"$1\" is \"$got\", expected \"$2\""; }
assert_backups()      {
    local n
    n=$(find "$STEAM/config" -name 'config.vdf.bak-*' | wc -l)
    [[ "$n" == "$1" ]] || fail_test "$n config.vdf backups, expected $1"
}
assert_downloaded()   { grep -q "/$1\$" "$FAKE_SERVER/requests.log" 2>/dev/null || fail_test "$1 was not downloaded"; }
assert_not_downloaded() { ! grep -q "/$1\$" "$FAKE_SERVER/requests.log" 2>/dev/null || fail_test "$1 should not be downloaded"; }
