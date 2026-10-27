#!/usr/bin/env python3
"""List or set the dates of files in a 140K ProDOS disk image.

    prodos_dates.py IMAGE
        List every file, including those in subdirectories, with its
        modification and creation dates.

    prodos_dates.py IMAGE PATH mod|create YYYY-MM-DD HH:MM
    prodos_dates.py IMAGE PATH mod|create none
        Set PATH's modification or creation date and time, or clear it.
        PATH is relative to the volume, e.g. SAMPLE or SUB/INNER.

Handles DOS-ordered (.dsk/.do) and ProDOS-ordered (.po) images.
"""
import sys

BLOCK = 512
ENTRY_LEN = 0x27
OFFSETS = {'mod': 0x21, 'create': 0x18}
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


def byte_offset(name, block, pos):
    """Offset in the image of byte pos of a block."""
    half, rest = divmod(pos, 256)
    return block_offsets(name, block)[half] + rest


def decode(date, time):
    if date == 0:
        return '<NO DATE>       '
    year = date >> 9
    year += 2000 if year < 40 else 1900
    return '%04d-%02d-%02d %02d:%02d' % (
        year, (date >> 5) & 0x0F, date & 0x1F, time >> 8, time & 0xFF)


def entries(image, name, key_block=2, prefix=''):
    """Yield (path, file type, entry) for each file in a directory and
    its subdirectories, where entry maps byte offsets within the entry to
    offsets in the image."""
    block = key_block
    first = True
    while block:
        data = read_block(image, name, block)
        for i in range(13):
            pos = 4 + i * ENTRY_LEN
            if first and i == 0:
                continue                    # directory header
            storage_len = data[pos]
            if storage_len >> 4 == 0:
                continue                    # deleted entry
            fname = data[pos + 1:pos + 1 + (storage_len & 0x0F)].decode()
            entry = {j: byte_offset(name, block, pos + j) for j in range(ENTRY_LEN)}
            yield prefix + fname, data[pos + 0x10], entry
            if storage_len >> 4 == 0x0D:    # subdirectory
                key = data[pos + 0x11] | data[pos + 0x12] << 8
                yield from entries(image, name, key, prefix + fname + '/')
        first = False
        block = data[2] | data[3] << 8


def stamp(image, entry, field):
    o = OFFSETS[field]
    date = image[entry[o]] | image[entry[o + 1]] << 8
    time = image[entry[o + 2]] | image[entry[o + 3]] << 8
    return decode(date, time)


def main(argv):
    image_name = argv[1]
    image = bytearray(open(image_name, 'rb').read())
    if len(argv) == 2:
        print('%-20s %-4s %-16s  %s' % ('NAME', 'TYPE', 'MODIFIED', 'CREATED'))
        for path, ftype, entry in entries(image, image_name):
            print('%-20s $%02X  %s  %s' % (path, ftype, stamp(image, entry, 'mod'),
                                           stamp(image, entry, 'create')))
        return 0
    target, field = argv[2].upper(), argv[3]
    if argv[4] == 'none':
        value = [0, 0, 0, 0]
    else:
        y, mo, d = (int(x) for x in argv[4].split('-'))
        h, mi = (int(x) for x in argv[5].split(':'))
        date = (y % 100) << 9 | mo << 5 | d
        value = [date & 0xFF, date >> 8, mi, h]
    for path, _, entry in entries(image, image_name):
        if path == target:
            for j, v in enumerate(value):
                image[entry[OFFSETS[field] + j]] = v
            open(image_name, 'wb').write(image)
            return 0
    print('%s: not found' % target, file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
