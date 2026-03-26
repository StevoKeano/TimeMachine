# tm_versions

**Browse every Time Machine snapshot version of any file — from the command line.**

macOS Time Machine silently stores dozens of local APFS snapshots of your disk. The problem: Apple gives you no way to browse individual file versions across those snapshots without opening the full Time Machine UI, which doesn't even work for hidden files or dotfiles.

`tm_versions.sh` fixes that. Give it any absolute file path and it mounts every local snapshot, finds the file, deduplicates by MD5, and prints ready-to-run restore commands for each unique version.

---

## Features

- Lists every snapshot that contains the target file
- Skips unchanged versions — only flags content that actually differs
- Prints copy-paste restore commands for each unique version
- Works on hidden files and dotfiles that Finder/Time Machine UI can't see
- Recovers files to `/tmp/filename.v1`, `.v2`, etc. for safe comparison before overwriting

---

## Requirements

- macOS with APFS and Time Machine local snapshots enabled
- `sudo` access
- Tested on macOS Sequoia (15.x)

---

## Installation

```bash
curl -O https://raw.githubusercontent.com/StevoKeano/tm-versions/main/tm_versions.sh
chmod +x tm_versions.sh
```

---

## Usage

```bash
sudo ./tm_versions.sh /absolute/path/to/your/file
```

### Example

```bash
sudo ./tm_versions.sh /Users/Steve/.openclaw/openclaw.json
```

### Example Output

```
Searching Time Machine snapshots for: /Users/Steve/.openclaw/openclaw.json
==================================================

----------------------------------------------------------------------
VERSION 1       com.apple.TimeMachine.2026-03-25-111926.local  Mar 25 01:14   3223 bytes  7f7c82fd...

  # Restore commands for VERSION 1:
  sudo mount_apfs -s com.apple.TimeMachine.2026-03-25-111926.local /dev/disk1s1 /tmp/tm_snapmnt
  cp "/tmp/tm_snapmnt/Users/Steve/.openclaw/openclaw.json" /tmp/openclaw.json.v1
  sudo umount /tmp/tm_snapmnt

----------------------------------------------------------------------
  unchanged     com.apple.TimeMachine.2026-03-25-121826.local  Mar 25 01:14   3223 bytes  7f7c82fd...

----------------------------------------------------------------------
VERSION 2       com.apple.TimeMachine.2026-03-25-132206.local  Mar 25 13:14   3246 bytes  4557f36d...

  # Restore commands for VERSION 2:
  sudo mount_apfs -s com.apple.TimeMachine.2026-03-25-132206.local /dev/disk1s1 /tmp/tm_snapmnt
  cp "/tmp/tm_snapmnt/Users/Steve/.openclaw/openclaw.json" /tmp/openclaw.json.v2
  sudo umount /tmp/tm_snapmnt

======================================================================
Total unique versions found: 6
```

---

## Restoring a Version

Copy the restore commands from the output and run them. Each version is saved to `/tmp/filename.vN`. Compare before overwriting:

```bash
diff /tmp/openclaw.json.v3 ~/.openclaw/openclaw.json
```

Then restore:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak-$(date +%Y%m%d-%H%M%S)
cp /tmp/openclaw.json.v3 ~/.openclaw/openclaw.json
```

---

## Notes

- Only **local** APFS snapshots are searched. External Time Machine drives have a different path structure.
- The script assumes your data volume is `disk1s1`. If yours differs, edit the `DISK` variable at the top of the script.
- Snapshots are hourly but macOS purges them when disk space is needed — they are not a substitute for a proper backup drive.
- `sudo` is required to mount APFS snapshots.

---

## Why This Exists

Apple's Time Machine UI won't show hidden files or dotfiles. Finder search doesn't index inside snapshots. `tmutil restore` has confusing syntax. Mounting APFS snapshots requires knowing obscure `diskutil` and `mount_apfs` incantations.

This script does all of that for you in one command.

---

## License

MIT

---

## Author

[StevoKeano](https://github.com/StevoKeano)
