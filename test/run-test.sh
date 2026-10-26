#!/bin/bash
#
# Boot a disk with TOUCH in LinApple on a virtual X display, type a series
# of touch commands as a user would, and save screenshots of the results.
# The directory dates on the disk are listed before and after.
#
# Usage: test/run-test.sh [DISK]      (default: touch.dsk)
#
# Needs Xvfb, xdotool, ImageMagick (import), and linapple.
#
set -e
cd "$(dirname "$0")/.."
DISK=${1:-touch.dsk}
OUT=test/out
WORK=$OUT/work.dsk
DATES=test/prodos_dates.py
DISPLAY_NUM=:99

mkdir -p $OUT
rm -f $OUT/*.png
cp "$DISK" $WORK

# Give SAMPLE an old date so the change is obvious
$DATES $WORK SAMPLE 1990-01-02 03:04
echo "== Before"
$DATES $WORK

if ! xdpyinfo -display $DISPLAY_NUM >/dev/null 2>&1; then
    Xvfb $DISPLAY_NUM -screen 0 1024x768x24 >/dev/null 2>&1 &
    XVFB_PID=$!
    sleep 2
fi
export DISPLAY=$DISPLAY_NUM

SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy \
    linapple -c linapple.conf --autoboot --d1 $WORK >$OUT/linapple.log 2>&1 &
LINAPPLE_PID=$!
cleanup() {
    kill $LINAPPLE_PID 2>/dev/null || true
    wait $LINAPPLE_PID 2>/dev/null || true
    [ -n "$XVFB_PID" ] && kill $XVFB_PID 2>/dev/null || true
}
trap cleanup EXIT

sleep 10                                    # boot to the BASIC prompt
xdotool windowfocus "$(xdotool search --name 'Emulator' | head -1)"
sleep 0.5

# Type a line and press RETURN
line() {
    xdotool type --delay 90 -- "$1"
    xdotool key Return
    sleep "${2:-3}"
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

line "HOME" 1
touch SAMPLE                    # partial pathname with no prefix set
touch newfile                   # does not exist: created; lowercase folded
touch /BOOT/TOUCH               # full pathname
touch NO.SUCH.DIR/X             # error reporting
touch ""                        # empty line: does nothing
line "PREFIX /BOOT"
touch NEWFILE                   # partial pathname with the prefix set
shot 1-touch

line "HOME" 1
line "CATALOG"
shot 2-catalog

cleanup
trap - EXIT
echo "== After"
$DATES $WORK
