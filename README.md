# GE-Proton Pilot

A small helper that keeps **GE-Proton** up to date for Steam on Linux.

GE-Proton is a community-made version of Proton, the tool Steam uses to run
Windows games on Linux. It often fixes games that don't work with Steam's own
Proton. This script saves you from downloading, unpacking and setting it up
by hand.

> **Credit:** GE-Proton is created and maintained by
> [GloriousEggroll](https://github.com/GloriousEggroll) and its contributors:
> **[github.com/GloriousEggroll/proton-ge-custom](https://github.com/GloriousEggroll/proton-ge-custom)**.
> GE-Proton Pilot only downloads and sets up their releases. It is not
> affiliated with the GE-Proton project. All the credit for making games
> run better goes to them. If GE-Proton helps you, consider supporting
> their work.

## What it does

Each time you run it, the script:

1. **Checks for a new version.** It asks GitHub for the newest GE-Proton release.
2. **Installs it.** It downloads the correct file for your computer (normal
   PCs or ARM devices) and checks it against the official checksum, so a
   broken or tampered download is never installed.
3. **Sets it as Steam's default.** Steam uses the default for every game you
   haven't set to a version yourself. It always asks first, closes Steam for
   a moment if needed, and backs up Steam's settings before changing
   anything. Games set to an older build of the same series (for example
   GE-Proton11-8 when GE-Proton11-9 comes out) can be switched along with it.
   Games set to another series, such as GE-Proton10, stay on it. The script
   tells you which ones these are.
4. **Spots wrong downloads.** If a GE-Proton version made for a different
   kind of PC is installed (for example an ARM build on a normal PC), it is
   marked as **"wrong type for this PC"**. If Steam is set to use one, the
   script warns you and offers to fix it.
5. **Keeps older series up to date too.** If you also use an older series
   (see [Several GE-Proton series side by side](#several-ge-proton-series-side-by-side)),
   it offers that series' newest build and to switch the games that use it.
6. **Offers to clean up.** If older builds are still installed, it shows how
   much space they use and asks whether to delete them. Every version Steam
   is set to use is always kept. An older series that no game uses, for
   example GE-Proton10 left over from before GE-Proton11, gets its own
   question; if you keep it, you aren't asked about it again. Nothing is
   deleted unless you say yes.

It asks a simple yes/no question before every step, and nothing changes
without your answer.

## Requirements

- **Linux** with **Steam**, installed in any of these ways:
  - from the Steam website or your Linux package manager (for example `steam`
    on Ubuntu or Linux Mint)
  - as a **Flatpak** (for example from Flathub or the Software Manager)
  - as a **Snap**

  If more than one is installed, the script asks which one to use.

  > **Note:** Flatpak and Snap support has so far only been tested in the
  > automated tests, not with a real Flatpak or Snap Steam. If something
  > doesn't work there, please
  > [open an issue](https://github.com/schaetzlein/ge-proton-pilot/issues).
- **curl** and **python3**, which most Linux systems already have. If one is
  missing, the script tells you which one and how to install it, for example:

  ```bash
  sudo apt install curl python3
  ```

## Install

1. Download `ge-proton-pilot.sh` from this page (click the file, then the
   **Download raw file** button), or run:

   ```bash
   curl -LO https://raw.githubusercontent.com/schaetzlein/ge-proton-pilot/main/ge-proton-pilot.sh
   ```

2. Make it runnable (you only need to do this once):

   ```bash
   chmod +x ge-proton-pilot.sh
   ```

Keep the file somewhere it can stay, for example in your home folder.

## Usage

Open a terminal in the folder where you saved the file and run:

```bash
./ge-proton-pilot.sh
```

Then answer the questions. A typical run looks like this:

```text
  ▌ Your current setup

    Steam:                   Steam (standard install)
    Installed versions:      GE-Proton11-8-x86_64
    Steam is using:          GE-Proton11-8-x86_64

  ▌ Checking for updates

    Looking for the newest version online...
    Newest version:          GE-Proton11-9-x86_64

    ✔ A new version is available!

  ➜ Download and install GE-Proton11-9-x86_64 now? (about 565 MB) [Y/n]

  ▌ Installing GE-Proton11-9-x86_64

    Downloading...
    ████████████████████░░░░░░░░░░  66%  373 / 565 MB
```

Press **Enter** to accept the suggested answer (the capital letter), or
type `y` or `n` and press **Enter**. Run the script again whenever you want
to check for updates.

### Desktop shortcut

To start the tool by double-clicking an icon on your desktop, open a terminal
in the folder where `ge-proton-pilot.sh` is and run:

```bash
ln -s "$PWD/ge-proton-pilot.sh" "$(xdg-user-dir DESKTOP)/GE-Proton Pilot"
```

This puts a link called **GE-Proton Pilot** on your desktop. `xdg-user-dir DESKTOP` finds
your desktop folder, even if it has a different name in your language
(for example `Schreibtisch`). Because it's a link, don't move or delete the
original file afterwards.

When you double-click the icon:

- **Linux Mint (Cinnamon):** choose **Run in Terminal**.
- **Ubuntu (GNOME):** right-click the icon and choose **Allow Launching**
  once, then right-click → **Run as a Program**.
- **Other desktops:** if your desktop runs the script without opening a
  terminal window, start it from a terminal as shown above instead, since the
  tool needs a window to ask its questions.

The window stays open at the end until you press **Enter**, so you can read
what happened.

### Several GE-Proton series side by side

GE-Proton comes in series: the number after `GE-Proton` (9, 10, 11). Only one
series is made at a time. When a new series starts, the old one is finished
and gets no more updates: **GE-Proton9** ended with GE-Proton9-27 and
**GE-Proton10** with GE-Proton10-34. The script makes the newest series
Steam's default.

If a game works better with an older series, you can keep that series
installed next to the current one and switch games between them in Steam.
To install an older series, run:

```bash
./ge-proton-pilot.sh --install 10              # newest GE-Proton10 (GE-Proton10-34)
./ge-proton-pilot.sh --install GE-Proton9-27   # or an exact version
```

This doesn't change Steam's default. To choose a version for one game,
right-click the game in Steam → **Properties** → **Compatibility**, turn on
**Force the use of a specific Steam Play compatibility tool**, and pick the
version.

From then on, each series is treated separately:

- A version a game is set to is never offered for deletion.
- A series you installed with `--install` is never offered for deletion.
- An older series that no game uses is probably left over from when it was
  the newest. Clean-up asks once whether to delete it. If you keep it, the
  script remembers that in `~/.config/ge-proton-pilot/keep` (one series
  number per line) and doesn't ask again. To be asked again, delete that
  file or remove the number from it.
- When you switch the default to a new build, only games on the same series
  can be moved along. Games on another series stay where they are, and the
  script lists them.
- If a newer build of an older series you use exists, the script offers it
  and asks whether to move that series' games to it.

GE-Proton9 and 10 were only made for normal (x86_64) PCs, not for ARM
devices. To remove a series you chose to keep, close Steam and delete its
folder from `compatibilitytools.d` in Steam's folder (for standard Steam,
`~/.steam/steam/compatibilitytools.d`), or remove its number from the keep
file so clean-up asks again.

## One-time setup in Steam

The script can only switch Steam to GE-Proton once Steam has saved a
compatibility setting. If you have never changed it, the script stops at
this point and shows these steps. You only need to do them once:

1. Open Steam.
2. Click **Steam** (top left), then **Settings**.
3. Click **Compatibility** on the left.
4. Turn on **Enable Steam Play for all other titles**.
5. In the list below it, choose the GE-Proton version the script installed.
6. Click **Restart** when Steam asks.

After that, the script switches versions for you automatically.

## Important: it edits Steam's settings file

To set GE-Proton as the default, the script **changes Steam's settings file**,
`config.vdf`. Where it is depends on how Steam is installed:

| Steam    | Settings file                                                     |
|----------|-------------------------------------------------------------------|
| Standard | `~/.steam/steam/config/config.vdf`                                |
| Flatpak  | `~/.var/app/com.valvesoftware.Steam/data/Steam/config/config.vdf` |
| Snap     | `~/snap/steam/common/.steam/steam/config/config.vdf`              |

To keep this safe, it:

- **asks you first** and closes Steam before editing (Steam would otherwise
  overwrite the change)
- **makes a backup** next to the file every time, named like
  `config.vdf.bak-20261018-153000`, and keeps the 3 newest backups. If the
  backup can't be made, nothing is changed.
- only changes the compatibility tool setting and leaves the rest of the file alone

**To undo a change:** close Steam, then replace `config.vdf` with one of the
backups (standard Steam shown here):

```bash
cp ~/.steam/steam/config/config.vdf.bak-YYYYMMDD-HHMMSS ~/.steam/steam/config/config.vdf
```

## Options for advanced use

Without options, the script asks before every step. These options are for
running it from other scripts or on a schedule:

| Option         | What it does |
|----------------|--------------|
| `--check`      | Only checks. Prints whether an update is available and changes nothing. |
| `--auto`       | Installs the newest version and makes it Steam's default **without asking**. Only runs while Steam is closed. Games you set to a specific version and old versions are left alone. |
| `--install VERSION` | Installs one specific version **without** changing Steam's default, for example for a game that needs an older one. `VERSION` is a series like `10` (its newest release) or an exact version like `GE-Proton10-34`. Clean-up never offers to delete that series afterwards. Steam may stay open; restart it afterwards so the version shows up. |
| `--steam KIND` | Which Steam to use if more than one is installed: `native`, `flatpak` or `snap`. Needed with `--check`, `--auto` or `--install` in that case. |
| `-h`, `--help` | Shows a short help text. |

Exit codes:

| Code | Meaning |
|------|---------|
| 0    | Everything worked, or nothing to do |
| 1    | Something went wrong (the message says what) |
| 2    | Wrong option, or more than one Steam and no `--steam` given |
| 3    | `--auto` only: Steam is running, so nothing was changed |
| 10   | `--check` only: an update is available, or installed but not used by Steam yet |

Example: check, and update only if there is something to do:

```bash
./ge-proton-pilot.sh --check
if [ $? -eq 10 ]; then
    ./ge-proton-pilot.sh --auto
fi
```

## Troubleshooting

- **"GitHub is getting too many update checks from your internet connection."**
  GitHub limits how often it can be asked without an account. Wait until the
  time shown and try again.
- **"Steam did not close by itself."** Close Steam yourself (Steam menu →
  Exit) and run the script again.
- **A version is marked "wrong type for this PC".** It was made for a
  different processor and can't run on your PC. The cleanup step offers to
  delete it.

## For developers: running the tests

The tests run the script in a fake environment: a temporary home folder,
made-up Steam settings, and stand-ins for `curl`, `pgrep` and `steam`. They
never touch your real Steam or go online.

```bash
tests/run.sh            # run everything (also runs shellcheck if installed)
tests/run.sh cleanup    # run only tests whose name contains "cleanup"
```

To also run [shellcheck](https://www.shellcheck.net/), install it with
`sudo apt install shellcheck`. To use a copy that isn't on your PATH, set
`SHELLCHECK=/path/to/shellcheck`.

## License

[MIT](LICENSE). GE-Proton itself has its own license; see the
[GE-Proton project](https://github.com/GloriousEggroll/proton-ge-custom).
