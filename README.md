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
3. **Sets it as Steam's default.** It tells Steam to use the new version for
   your games. It always asks first, closes Steam for a moment if needed,
   and backs up Steam's settings before changing anything.
4. **Offers to clean up.** If older GE-Proton versions are still installed,
   it shows how much space they use and asks whether to delete them. They
   are only deleted if you say yes.

It asks a simple yes/no question before every step, and nothing changes
without your answer.

## Requirements

- **Linux** with **native Steam**, meaning Steam installed from the Steam
  website or your distribution's package (for example `steam` on Ubuntu or
  Linux Mint).
  The **Flatpak** and **Snap** versions of Steam are **not** supported.
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

## Usage

Open a terminal in the folder where you saved the file and run:

```bash
./ge-proton-pilot.sh
```

Then answer the questions. A typical run looks like this:

```text
  ▌ Your current setup

    Installed versions:      GE-Proton10-3
    Steam is using:          GE-Proton10-3

  ▌ Checking for updates

    Looking for the newest version online...
    Newest version:          GE-Proton10-4

    ✔ A new version is available!

  ➜ Download and install GE-Proton10-4 now? (about 480 MB) [Y/n]
```

Press **Enter** to accept the suggested answer (the capital letter), or
type `y` or `n` and press **Enter**. Run the script again whenever you want
to check for updates.

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

To set GE-Proton as the default, the script **changes Steam's settings file**:

```text
~/.steam/steam/config/config.vdf
```

To keep this safe, it:

- **asks you first** and closes Steam before editing (Steam would otherwise
  overwrite the change)
- **makes a backup** next to the file every time, named like
  `config.vdf.bak-20261018-153000`, and keeps the 3 newest backups
- only changes the compatibility tool setting and leaves the rest of the file alone

**To undo a change:** close Steam, then replace `config.vdf` with one of the
backups:

```bash
cp ~/.steam/steam/config/config.vdf.bak-YYYYMMDD-HHMMSS ~/.steam/steam/config/config.vdf
```

## License

[MIT](LICENSE)
