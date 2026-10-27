#!/bin/bash
#
# Boot a disk with TOUCH in LinApple on a virtual X display, type a series
# of touch commands as a user would, and save screenshots of the results.
# The directory dates on the disk are listed before and after.
#
# It runs twice: with the clock card from linapple.conf, and with the
# clock card removed, where touch asks for the date.
#
# Usage: test/run-test.sh [DISK]      (default: touch.dsk)
#
# Needs Xvfb, xdotool, ImageMagick (import), and linapple.
#
set -e
cd "$(dirname "$0")/.."
DISK=${1:-touch.dsk}
OUT=test/out
DATES=test/prodos_dates.py
DISPLAY_NUM=:99

mkdir -p $OUT
rm -f $OUT/*.png $OUT/*.dsk
sed 's/^Slot 4 = Clock Card/Slot 4 = None/' linapple.conf > $OUT/noclock.conf

if ! xdpyinfo -display $DISPLAY_NUM >/dev/null 2>&1; then
    Xvfb $DISPLAY_NUM -screen 0 1024x768x24 >/dev/null 2>&1 &
    XVFB_PID=$!
    sleep 2
fi
export DISPLAY=$DISPLAY_NUM

stop() {
    [ -n "$LINAPPLE_PID" ] && kill $LINAPPLE_PID 2>/dev/null || true
    [ -n "$LINAPPLE_PID" ] && wait $LINAPPLE_PID 2>/dev/null || true
    LINAPPLE_PID=
}
cleanup() {
    stop
    [ -n "$XVFB_PID" ] && kill $XVFB_PID 2>/dev/null || true
}
trap cleanup EXIT

# Copy the disk (or the one given third), give SAMPLE an old date so the
# change is obvious, and boot it with the config file given
boot() {
    WORK=$OUT/$1.dsk
    cp "${3:-$DISK}" $WORK
    $DATES $WORK SAMPLE mod 1990-01-02 03:04
    echo "== $1: before"
    $DATES $WORK
    SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy \
        linapple -c $2 --autoboot --d1 $WORK >$OUT/$1.log 2>&1 &
    LINAPPLE_PID=$!
    sleep 10                                # boot to the BASIC prompt
    xdotool windowfocus "$(xdotool search --name 'Emulator' | head -1)"
    sleep 0.5
}
finish() {
    stop
    echo "== $1: after"
    $DATES $OUT/$1.dsk
}

# Type a line and press RETURN
line() {
    xdotool type --delay 90 -- "$1"
    xdotool key Return
    sleep "${2:-3}"
}
# Type text without pressing RETURN
text() {
    xdotool type --delay 90 -- "$1"
}
# Press keys by X key name, e.g. Delete, Left, Right, ctrl+x, Return.
# Each key is released at once: LinApple runs fast while the disk is
# busy, so a key held even briefly then auto-repeats.
keys() {
    for k in "$@"; do
        xdotool key "$k"
        sleep 0.15
    done
    if [ "${@: -1}" = Return ]; then
        sleep 3                 # let touch finish before typing more
    else
        sleep 1
    fi
}
# Wait for a disk write to finish before typing more
wait_disk() {
    sleep 3
}
# Run touch on a pathname
touch() {
    line "-TOUCH"
    line "$1"
}
shot() {
    import -window root -crop 640x400+200+180 "$OUT/$1.png"
    echo "screenshot: $OUT/$1.png"
}

boot clock linapple.conf
line "HOME" 1
touch SAMPLE                    # partial pathname with no prefix set
touch newfile                   # does not exist: created; lowercase folded
touch /TOUCH/TOUCH              # full pathname
touch NO.SUCH.DIR/X             # error reporting
touch ""                        # empty line: does nothing
line "PREFIX /TOUCH"
touch NEWFILE                   # partial pathname with the prefix set
shot 1-touch
line "HOME" 1
line "CATALOG"
shot 2-catalog
finish clock

boot noclock $OUT/noclock.conf
line "HOME" 1
touch SAMPLE                    # asks for the date
line ""                         # empty line: cancels
touch SAMPLE
line "32-JAN-26"                # no such day
line "29-FEB-25"                # not a leap year
line "15-XYZ-26"                # no such month
line "15-OCT-26 24:00"          # no such hour
line "15-OCT-26 12:60"          # no such minute
line "15-OCT-26 12:3X"          # junk after the time
shot 3-noclock-invalid
text "29-feb-24 13:4X"          # valid, in lowercase, once the X is
keys Delete                     # deleted
line "5"
touch NEWFILE                   # the date is set now: no question
touch SAMPLE
line "PRINT PEEK(49040);\",\";PEEK(49041);\",\";PEEK(49042);\",\";PEEK(49043)"
shot 4-noclock-set
line "HOME" 1
line "CATALOG"
shot 5-noclock-catalog
finish noclock

# Line editing with Delete and the arrow keys. In LinApple the host's
# Delete key is the Apple Delete key; Backspace is the left arrow.
boot editing linapple.conf
line "HOME" 1
line "-TOUCH"
text "SAMPLX"                   # Delete at the end of the line
keys Delete
line "E"
line "-TOUCH"
text "SAMXPLE"                  # Delete in the middle closes up the gap
keys Left Left Left Delete Right Right Right Return
line "-TOUCH"
text "NEWFILEXYZ"               # RETURN drops what is right of the cursor
keys Left Left Left Return
line "-TOUCH"
text "JUNK"                     # Ctrl-X cancels the line
keys ctrl+x
line "SAMPLE"
line "-TOUCH"
keys Delete Left Up Down        # nothing to delete or move over; up and
text "SAM"                      # down arrows are ignored
keys Up Down
line "PLE"
shot 7-editing

line "HOME" 1
line "-TOUCH"
text "SAMPLE$(printf 'Z%.0s' {1..30})"  # wraps onto the next line
shot 8-wrap-before
keys $(printf 'Delete %.0s' {1..30})    # delete back across the wrap
shot 8-wrap-deleted
keys Return
shot 8-wrap-after

line "PR#3"                     # the same in 80 columns
line "HOME" 1
line "-TOUCH"
text "SAMXPLE"
keys Left Left Left Delete Right Right Right Return
line "-TOUCH"
text "EIGHTXY"                  # creates EIGHTY
keys Left Delete Right Return
shot 9-80col
finish editing

# Creation dates. ProDOS 8 has no call to set one, so touch writes the
# directory entry itself. Make files that fill the volume directory's
# first block (12 entries after its header), so A1-A3 are in its second,
# and files in subdirectories.
SETUP=$OUT/setup-src.dsk
cp "$DISK" $SETUP
for f in F1 F2 F3 F4 F5; do
    printf '' | java -jar AppleCommander-ac-1.4.0.jar -p $SETUP $f TXT
done
if [ "$($DATES $SETUP | tail -n +2 | wc -l)" != 12 ]; then
    echo "the volume directory's first block is not full" >&2
    exit 1
fi
for f in A1 A2 A3; do
    printf '' | java -jar AppleCommander-ac-1.4.0.jar -p $SETUP $f TXT
done
boot create-setup linapple.conf $SETUP
line "CREATE SUB"
line "CREATE SUB/DEEP"
touch SUB/INNER
touch SUB/DEEP/FILE
touch SUB/DEEP/FILE2
finish create-setup
# Then clear their creation dates
for f in SAMPLE A1 A2 A3 SUB/INNER SUB/DEEP/FILE SUB/DEEP/FILE2; do
    $DATES $OUT/create-setup.dsk $f create none
done

boot create linapple.conf $OUT/create-setup.dsk
line "HOME" 1
touch SAMPLE
keys n                          # now, in lowercase
wait_disk
touch A1                        # in the second directory block
keys x e                        # x is not a choice: just a beep
line "31-JUN-85"                # no such day
line "15-JUL-85 09:30"
wait_disk
touch A2
keys I                          # ignore
touch A3
keys E
line ""                         # empty line: ignore
shot 10-create
line "HOME" 1
touch SUB/INNER                 # in a subdirectory
keys N
wait_disk
touch /TOUCH/SUB/DEEP/FILE      # two levels down, full pathname
keys E
line "4-JUL-76"
wait_disk
line "PREFIX /TOUCH/SUB"        # TOUCH is not in /TOUCH/SUB, so give
line "-/TOUCH/TOUCH"            # its full pathname
line "DEEP/FILE2"               # partial pathname with a prefix
keys N
wait_disk
line "-/TOUCH/TOUCH"
line "DEEP/FILE"                # has a creation date now: no question
shot 11-create-subdirs
finish create
echo "== create: AppleCommander can still read the disk"
java -jar AppleCommander-ac-1.4.0.jar -ll $OUT/create.dsk | grep "ProDOS format"

# A date without a time: the time becomes 00:00
boot notime $OUT/noclock.conf
line "HOME" 1
touch SAMPLE
line "1-JAN-00"
shot 6-notime
finish notime
