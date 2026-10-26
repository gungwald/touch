# touch

A `touch` command for the Apple II under ProDOS 8, written in 6502
assembly for the cc65 assembler (ca65). It sets a file's modification
date and time to the current date and time from the ProDOS clock. As
with Unix touch, a file that does not exist is created (as an empty TXT
file).

```
]-TOUCH
FILE TO TOUCH:SAMPLE
TOUCHED SAMPLE 26-OCT-26 11:20
```

The pathname may be partial or full (`/VOLUME/DIR/FILE`). If no prefix is
set, a partial pathname refers to BASIC.SYSTEM's default drive, as it does
for BASIC.SYSTEM's own commands. Pressing RETURN on an empty line exits.
MLI errors are reported by number and name, e.g. `ERROR $44 PATH NOT FOUND`.

### Without a clock

If ProDOS has no date, because there is no clock card and no date has
been set, touch asks for one:

```
]-TOUCH
FILE TO TOUCH:SAMPLE
NO DATE IS SET. ENTER TODAY'S DATE AS
DD-MON-YY OR DD-MON-YY HH:MM
DATE:29-FEB-24 13:45
TOUCHED SAMPLE 29-FEB-24 13:45
```

The time is optional; without it the time is set to 00:00. Dates that
don't exist, such as 31-APR-26 or 29-FEB-25, get `INVALID DATE` and the
question again. An empty line cancels and changes nothing.

The date is set in ProDOS as well as on the file. ProDOS uses it until
the computer is restarted: later touches use it without asking, and so
do files created or saved from BASIC.SYSTEM. With no clock it does not
advance, so update it by hand if the day changes.

## How it works

1. `GET_TIME` ($82) reads the clock into DATE/TIME at $BF90-$BF93. If they
   are still zero there is no clock, and touch asks for the date and
   writes it there itself.
2. `GET_FILE_INFO` ($C4) reads the file's access, type and aux type
   (`CREATE` ($C0) first if the file is not found).
3. `SET_FILE_INFO` ($C3) writes them back with the new modification
   date and time. Both calls share one parameter block, since their
   layouts line up.

## Building

Requires GNU make, cc65 (`dnf install cc65`), and Java for the included
AppleCommander.

```
make          # builds touch and touch.dsk
make cat      # lists the files on touch.dsk
```

`touch.dsk` is a bootable ProDOS 2.4.3 disk holding `TOUCH` (BIN, $2000)
and a small `SAMPLE` text file to try it on.

## Testing in LinApple

```
make test
```

boots `touch.dsk` in LinApple with `linapple.conf`. That config puts
LinApple's ThunderClock compatible clock card in slot 4. To try touch
without a clock, change `Slot 4 = Clock Card` to `Slot 4 = None`.

`test/run-test.sh` runs the tests automatically. It backdates `SAMPLE` to
1990, then boots LinApple on a virtual X display (Xvfb). It types a
series of touch commands with xdotool and saves screenshots to `test/out`.
It lists the modification dates read from the disk image before and
after (using `test/prodos_dates.py`). It then runs again with the clock
card removed, to test entering the date.

### Why ProDOS 2.4.3

A ThunderClock does not keep the year, so ProDOS works it out from the day
of the week using a table of years. The table in ProDOS 2.0.3 ends in the
1990s (October 26, 2026 comes out as 1998). ProDOS 2.4.3's table covers
the current years. `prodos-2.4.3-boot.dsk` is a ProDOS 2.0.3 boot disk
with PRODOS and BASIC.SYSTEM replaced by the 2.4.3 versions.

## How it was made

This program was vibe coded with
[Claude Code](https://claude.com/claude-code).

## License

touch is free software, licensed under the GNU General Public License
version 3. See [LICENSE](LICENSE).

The included third-party files, `AppleCommander-ac-1.4.0.jar` and the
ProDOS system files on `prodos-2.4.3-boot.dsk`, come under their own
terms.
