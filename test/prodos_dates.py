#!/usr/bin/env python3
"""List or set modification dates of files in a 140K ProDOS disk image.

    prodos_dates.py IMAGE                      list the volume directory
    prodos_dates.py IMAGE NAME YYYY-MM-DD HH:MM  set NAME's mod date/time

Handles DOS-ordered (.dsk/.do) and ProDOS-ordered (.po) images. Only the
volume directory is examined, which is all the touch tests need.
"""
import sys

BLOCK = 512
ENTRY_LEN = 0x27
# DOS 3.3 logical sectors holding the two halves of each ProDOS block
# within a track
DOS_SECTORS = [(0, 14), (13, 12), (11, 10), (9, 8), (7, 6), (5, 4), (3, 2), (1, 15)]


def block_offsets(image_name, block):
    if image_name.lower().endswith('.po'):
        return [block * BLOCK, block * BLOCK + 256]
    track, index = divmod(block, 8)
    return [(track * 16 + s) * 256 for s in DOS_SECTORS[index]]


def read_block(image, name, block):
    return b''.join(image[o:o + 256] for o in block_offsets(name, block))


def decode(date, time):
    if date == 0:
        return '<NO DATE>       '
    year = date >> 9
    year += 2000 if year < 40 else 1900
    return '%04d-%02d-%02d %02d:%02d' % (
        year, (date >> 5) & 0x0F, date & 0x1F, time >> 8, time & 0xFF)


def byte_offset(name, block, pos):
    """Offset in the image of byte pos of a block."""
    half, rest = divmod(pos, 256)
    return block_offsets(name, block)[half] + rest


def entries(image, name):
    """Yield (name, file type, offsets in the image of the mod date/time)."""
    block = 2
    first = True
    while block:
        data = read_block(image, name, block)
        for i in range(13):
            pos = 4 + i * ENTRY_LEN
            if first and i == 0:
                continue                    # volume directory header
            storage_len = data[pos]
            if storage_len >> 4 == 0:
                continue                    # deleted entry
            fname = data[pos + 1:pos + 1 + (storage_len & 0x0F)].decode()
            mod = [byte_offset(name, block, pos + 0x21 + j) for j in range(4)]
            yield fname, data[pos + 0x10], mod
        first = False
        block = data[2] | data[3] << 8


def main(argv):
    image_name = argv[1]
    image = bytearray(open(image_name, 'rb').read())
    if len(argv) == 2:
        for fname, ftype, mod in entries(image, image_name):
            date = image[mod[0]] | image[mod[1]] << 8
            time = image[mod[2]] | image[mod[3]] << 8
            print('%-15s $%02X  %s' % (fname, ftype, decode(date, time)))
        return 0
    target, day, hhmm = argv[2].upper(), argv[3], argv[4]
    y, mo, d = (int(x) for x in day.split('-'))
    h, mi = (int(x) for x in hhmm.split(':'))
    date = (y % 100) << 9 | mo << 5 | d
    for fname, _, mod in entries(image, image_name):
        if fname == target:
            for o, value in zip(mod, (date & 0xFF, date >> 8, mi, h)):
                image[o] = value
            open(image_name, 'wb').write(image)
            return 0
    print('%s: not found' % target, file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
