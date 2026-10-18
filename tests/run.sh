#!/usr/bin/env bash
# Runs the GE-Proton Pilot tests in a fake environment (fake HOME, Steam
# folders, GitHub release, curl, pgrep and steam), then runs shellcheck.
# Usage: tests/run.sh [NAME-FILTER]
# Nothing on the real PC or online is touched.
#
# Note: Bash only shows read -p prompts on a real terminal, so the tests
# check what each answer did rather than the question text.
# shellcheck source-path=SCRIPTDIR

set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ./lib.sh

LATEST=GE-Proton11-9
NEW=GE-Proton11-9-x86_64
OLD=GE-Proton11-8-x86_64
ARM=GE-Proton11-9-aarch64

# ---------- Interactive mode ----------

publish_history() {  # the last GE-Proton9 and GE-Proton10 builds, then the current series
    publish_old_release GE-Proton9-27
    publish_old_release GE-Proton10-33
    publish_old_release GE-Proton10-34
    publish_release "$LATEST"
}

test_new_install() {
    publish_release "$LATEST"
    write_config proton_experimental
    # install: Enter (yes) | make it the default: Enter | start Steam: n | close: Enter
    run_script '\n\nn\n\n'
    assert_status 0 &&
    assert_output "A new version is available!" &&
    assert_output "Checked: the download is complete and genuine" &&
    assert_output "Done! Steam now uses $NEW" &&
    assert_installed "$NEW" &&
    assert_mapping 0 "$NEW" &&
    assert_backups 1 &&
    assert_not_downloaded "$ARM.tar.gz"
}

test_already_up_to_date() {
    publish_release "$LATEST"
    add_installed "$NEW"
    write_config "$NEW"
    run_script '\n'
    assert_status 0 &&
    assert_output "Everything is up to date." &&
    assert_no_output "Clean up" &&
    assert_not_downloaded "$NEW.tar.gz" &&
    assert_backups 0
}

test_installed_but_not_default() {
    publish_release "$LATEST"
    add_installed "$NEW"
    write_config proton_experimental
    run_script '\nn\n\n'
    assert_output "But Steam isn't using it yet." &&
    assert_not_downloaded "$NEW.tar.gz" &&
    assert_mapping 0 "$NEW"
}

test_no_stored_steam_setting_shows_manual_setup() {
    publish_release "$LATEST"
    write_config_without_mapping
    cp "$STEAM/config/config.vdf" "$WORK/before.vdf"
    run_script '\nn\n\n'
    assert_status 0 &&
    assert_installed "$NEW" &&
    assert_output "One-time setup in Steam" &&
    assert_output "choose $NEW" &&
    assert_backups 0 &&
    { cmp -s "$WORK/before.vdf" "$STEAM/config/config.vdf" || fail_test "config.vdf was changed"; }
}

test_pinned_games_setall() {
    publish_release "$LATEST"
    add_installed "$OLD"
    write_config "$OLD" 10="$OLD" 20=proton_9
    # install: Enter | option 1 (all games) | start Steam: n | delete old: y | close: Enter
    run_script '\n1\nn\ny\n\n'
    assert_output "You have 1 game set to an older GE-Proton11 version." &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 "$NEW" &&
    assert_mapping 20 proton_9
}

test_pinned_games_keep() {
    publish_release "$LATEST"
    add_installed "$OLD"
    write_config "$OLD" 10="$OLD"
    # install: Enter | option 2 (leave that game) | start Steam: n | close (no clean-up: a game uses it)
    run_script '\n2\nn\n\n'
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 "$OLD" &&
    assert_installed "$OLD" &&
    assert_no_output "Clean up"
}

test_setall_leaves_other_series_alone() {
    publish_history
    add_installed "$OLD" GE-Proton10-34
    write_config "$OLD" 10="$OLD" 20=GE-Proton10-34
    # install: Enter | option 1 (all games) | start Steam: n | delete old: y | close
    run_script '\n1\nn\ny\n\n'
    assert_output "1 game is set to GE-Proton10-34 and stays on it." &&
    assert_output "Use $NEW as the default, and for that game too" &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 "$NEW" &&
    assert_mapping 20 GE-Proton10-34 &&
    assert_installed GE-Proton10-34 &&
    assert_not_installed "$OLD"
}

test_other_series_only_is_mentioned() {
    publish_history
    add_installed "$OLD" GE-Proton10-34
    write_config "$OLD" 10=GE-Proton10-34 20=GE-Proton10-34
    # install: Enter | make it the default: Enter | start Steam: n | delete old: y | close
    run_script '\n\nn\ny\n\n'
    assert_output "2 games are set to GE-Proton10-34 and stay on it." &&
    assert_no_output "1) Use" &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 GE-Proton10-34 &&
    assert_mapping 20 GE-Proton10-34
}

test_cleanup_keeps_newest_of_each_series() {
    publish_history
    add_installed GE-Proton9-27 GE-Proton10-33 GE-Proton10-34 "$OLD" "$NEW"
    write_config "$NEW"
    run_script 'y\n\n'
    assert_output "Deleted GE-Proton10-33" &&
    assert_output "Deleted $OLD" &&
    assert_installed GE-Proton9-27 &&
    assert_installed GE-Proton10-34 &&
    assert_installed "$NEW" &&
    assert_not_installed GE-Proton10-33
}

test_cleanup_keeps_versions_games_use() {
    publish_history
    add_installed GE-Proton10-33 GE-Proton10-34 "$OLD" "$NEW"
    write_config "$NEW" 10=GE-Proton10-33
    run_script 'y\n\n'
    assert_output "Kept because Steam is set to use them: GE-Proton10-33" &&
    assert_output "Deleted $OLD" &&
    assert_installed GE-Proton10-33
}

test_older_series_is_updated_and_games_moved() {
    publish_history
    add_installed GE-Proton10-33 "$NEW"
    write_config "$NEW" 10=GE-Proton10-33 20="$NEW"
    # install 10-34: Enter | switch that game: Enter | start Steam: n | delete 10-33: y | close
    run_script '\n\nn\ny\n\n'
    assert_status 0 &&
    assert_output "Everything is up to date." &&
    assert_output "The newest GE-Proton10 is GE-Proton10-34" &&
    assert_installed GE-Proton10-34 &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 GE-Proton10-34 &&
    assert_mapping 20 "$NEW" &&
    assert_not_installed GE-Proton10-33
}

test_older_series_update_declined() {
    publish_history
    add_installed GE-Proton10-33 "$NEW"
    write_config "$NEW"
    run_script 'n\n\n'
    assert_output "Okay, nothing was installed." &&
    assert_not_downloaded GE-Proton10-34.tar.gz &&
    assert_installed GE-Proton10-33 &&
    assert_no_output "Clean up"
}

test_older_series_already_newest() {
    publish_history
    add_installed GE-Proton9-27 GE-Proton10-34 "$NEW"
    write_config "$NEW"
    run_script '\n'
    assert_status 0 &&
    assert_no_output "Update GE-Proton" &&
    assert_no_output "Clean up"
}

test_closes_and_restarts_running_steam() {
    publish_release "$LATEST"
    write_config proton_experimental
    touch "$FAKE_STEAM_RUNNING"
    # install | use it | close Steam: Enter | start Steam: Enter | close window
    run_script '\n\n\n\n\n'
    assert_output "Closing Steam" &&
    assert_output "Steam is starting." &&
    assert_mapping 0 "$NEW" &&
    { grep -qx 'steam -shutdown' "$FAKE_SERVER/requests.log" || fail_test "Steam was not shut down"; }
}

test_wrong_arch_build_is_flagged_and_replaced() {
    publish_release "$LATEST"
    add_installed "$ARM"
    write_config "$ARM"
    # install | use it | start Steam: n | delete wrong build: Enter (default yes) | close
    run_script '\n\nn\n\n\n'
    assert_output "$ARM (wrong type for this PC)" &&
    assert_output "Steam is set to the wrong type of GE-Proton" &&
    assert_output "A new version is available!" &&
    assert_installed "$NEW" &&
    assert_not_installed "$ARM" &&
    assert_mapping 0 "$NEW"
}

test_wrong_arch_default_fixed_without_update() {
    publish_release "$LATEST"
    add_installed "$OLD" "$ARM"
    write_config "$ARM"
    # install: n | switch to the usable older version: Enter | start Steam: n | delete: Enter | close
    run_script 'n\n\nn\n\n\n'
    assert_output "Okay, nothing was installed." &&
    assert_output "Make $OLD the default" &&
    assert_mapping 0 "$OLD" &&
    assert_installed "$OLD" &&
    assert_not_installed "$ARM"
}

test_arm_pc_downloads_arm_build() {
    export FAKE_ARCH=aarch64
    publish_release "$LATEST"
    add_installed GE-Proton10-4
    write_config proton_experimental
    run_script '\n\nn\nn\n\n'
    assert_output "GE-Proton10-4 (wrong type for this PC)" &&
    assert_installed "$ARM" &&
    assert_not_downloaded "$NEW.tar.gz" &&
    assert_mapping 0 "$ARM"
}

test_cleanup_deletes_old_versions() {
    publish_release "$LATEST"
    add_installed "$OLD" "$NEW"
    write_config "$NEW"
    run_script 'y\n\n'
    assert_output "Clean up" &&
    assert_output "Deleted $OLD" &&
    assert_not_installed "$OLD" &&
    assert_installed "$NEW"
}

test_cleanup_keeps_old_versions_by_default() {
    publish_release "$LATEST"
    add_installed "$OLD" "$NEW"
    write_config "$NEW"
    run_script '\n\n'
    assert_output "Okay, they stay." &&
    assert_installed "$OLD"
}

test_damaged_download_is_not_installed() {
    publish_release "$LATEST"
    write_config proton_experimental
    echo garbage >> "$FAKE_SERVER/$NEW.tar.gz"
    run_script '\n\n'
    assert_status 1 &&
    assert_output "The download is damaged" &&
    assert_not_installed "$NEW" &&
    assert_mapping 0 proton_experimental
}

test_flatpak_steam() {
    publish_release "$LATEST"
    rm -rf "$HOME/.steam"
    STEAM="$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    mkdir -p "$STEAM/config"
    write_config proton_experimental
    touch "$FAKE_STEAM_RUNNING"
    run_script '\n\n\n\n\n'
    assert_output "Steam (Flatpak)" &&
    assert_installed "$NEW" &&
    assert_mapping 0 "$NEW" &&
    { grep -qx 'flatpak run com.valvesoftware.Steam -shutdown' "$FAKE_SERVER/requests.log" ||
        fail_test "Flatpak Steam was not shut down"; }
}

test_asks_which_steam() {
    publish_release "$LATEST"
    mkdir -p "$HOME/snap/steam/common/.steam/steam"
    write_config "$NEW"
    add_installed "$NEW"
    run_script '1\n\n'
    assert_output "More than one Steam is installed" &&
    assert_output "Steam (standard install)" &&
    assert_output "Everything is up to date."
}

test_no_steam() {
    rm -rf "$HOME/.steam"
    run_script '\n'
    assert_status 1 &&
    assert_output "Steam was not found on this PC."
}

# ---------- --check / --auto / --help ----------

test_check_update_available() {
    publish_release "$LATEST"
    add_installed "$OLD"
    write_config "$OLD"
    run_script '' --check
    assert_status 10 &&
    assert_output "Update available: $NEW"
}

test_check_up_to_date() {
    publish_release "$LATEST"
    add_installed "$NEW"
    write_config "$NEW"
    run_script '' --check
    assert_status 0 &&
    assert_output "Up to date: $NEW"
}

test_auto_installs_and_sets_default() {
    publish_release "$LATEST"
    add_installed "$OLD"
    write_config "$OLD" 10="$OLD"
    run_script '' --auto
    assert_status 0 &&
    assert_installed "$NEW" &&
    assert_installed "$OLD" &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 "$OLD" &&
    assert_backups 1
}

test_auto_refuses_while_steam_runs() {
    publish_release "$LATEST"
    write_config proton_experimental
    touch "$FAKE_STEAM_RUNNING"
    run_script '' --auto
    assert_status 3 &&
    assert_output "Steam is running" &&
    assert_not_installed "$NEW" &&
    assert_mapping 0 proton_experimental
}

test_auto_without_stored_setting() {
    publish_release "$LATEST"
    write_config_without_mapping
    run_script '' --auto
    assert_status 1 &&
    assert_installed "$NEW" &&
    assert_output "One-time setup in Steam"
}

test_help() {
    run_script '' --help
    assert_status 0 &&
    assert_output "--check" &&
    assert_output "--auto"
}

test_unknown_option() {
    run_script '' --bogus
    assert_status 2 &&
    assert_output "Unknown option: --bogus"
}

# ---------- --install ----------

test_install_newest_of_old_series() {
    publish_history
    write_config "$NEW" 10="$NEW"
    run_script '' --install 10
    assert_status 0 &&
    assert_installed GE-Proton10-34 &&
    assert_not_downloaded GE-Proton10-33.tar.gz &&
    assert_output "Steam's default was not changed" &&
    assert_mapping 0 "$NEW" &&
    assert_mapping 10 "$NEW" &&
    assert_backups 0
}

test_install_exact_version() {
    publish_history
    write_config "$NEW"
    run_script '' --install GE-Proton9-27
    assert_status 0 &&
    assert_installed GE-Proton9-27 &&
    assert_output "Installed GE-Proton9-27"
}

test_install_already_installed() {
    publish_history
    add_installed GE-Proton10-34
    write_config "$NEW"
    run_script '' --install=10
    assert_status 0 &&
    assert_output "GE-Proton10-34 is already installed." &&
    assert_not_downloaded GE-Proton10-34.tar.gz
}

test_install_while_steam_runs() {
    publish_history
    write_config "$NEW"
    touch "$FAKE_STEAM_RUNNING"
    run_script '' --install 10
    assert_status 0 &&
    assert_installed GE-Proton10-34 &&
    assert_output "Restart Steam so GE-Proton10-34 shows up"
}

test_install_unknown_version() {
    publish_history
    write_config "$NEW"
    run_script '' --install 8
    assert_status 1 &&
    assert_output "GitHub has no GE-Proton release called GE-Proton8." &&
    run_script '' --install GE-Proton10-99
    assert_status 1 &&
    assert_output "GitHub has no GE-Proton release called GE-Proton10-99."
}

test_install_old_series_on_arm() {
    export FAKE_ARCH=aarch64
    publish_history
    write_config "$ARM"
    run_script '' --install 10
    assert_status 1 &&
    assert_output "GE-Proton10 has no build for this type of PC." &&
    assert_not_installed GE-Proton10-34
}

test_install_bad_argument() {
    run_script '' --install latest
    assert_status 2 &&
    assert_output "--install needs a series like 10"
}

# ---------- GitHub errors ----------

test_rate_limit() {
    publish_release "$LATEST"
    write_config proton_experimental
    export FAKE_API_STATUS=403 FAKE_API_HEADERS=$'x-ratelimit-remaining: 0\r\nx-ratelimit-reset: 1792332000'
    run_script '\n'
    assert_status 1 &&
    assert_output "too many update checks" &&
    assert_output "try again after"
}

test_github_error() {
    publish_release "$LATEST"
    write_config proton_experimental
    export FAKE_API_STATUS=502
    run_script '' --check
    assert_status 1 &&
    assert_output "GitHub answered with an error (code 502)"
}

test_offline() {
    write_config proton_experimental
    export FAKE_OFFLINE=1
    run_script '' --check
    assert_status 1 &&
    assert_output "Couldn't reach GitHub"
}

# ---------- Runner ----------

passed=0 failed=0 failed_names=()
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    [[ -n "${1:-}" && "$t" != *"$1"* ]] && continue
    if result=$( (setup_env; trap 'rm -rf "$WORK"' EXIT; "$t" || { while IFS= read -r l; do echo "      | $l"; done <<<"$OUTPUT"; exit 1; }) 2>&1 ); then
        echo "  ok    ${t#test_}"
        passed=$(( passed + 1 ))
    else
        echo "  FAIL  ${t#test_}"
        echo "$result"
        failed=$(( failed + 1 ))
        failed_names+=("${t#test_}")
    fi
done

echo
SHELLCHECK="${SHELLCHECK:-shellcheck}"
if command -v "$SHELLCHECK" >/dev/null; then
    if "$SHELLCHECK" -x ../ge-proton-pilot.sh run.sh lib.sh fakebin/*; then
        echo "  ok    shellcheck"
        passed=$(( passed + 1 ))
    else
        echo "  FAIL  shellcheck"
        failed=$(( failed + 1 ))
        failed_names+=(shellcheck)
    fi
else
    echo "  skip  shellcheck (not installed: sudo apt install shellcheck)"
fi

echo
echo "$passed passed, $failed failed${failed_names[*]:+: ${failed_names[*]}}"
(( failed == 0 ))
