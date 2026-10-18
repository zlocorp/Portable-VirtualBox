"""Synthetic PE resource image; no executable code and no Oracle payload."""
import struct


def make_pe(resources, *, plus=False):
    names = list(resources)
    n = len(names)
    buf = bytearray(40 + 8 * n)
    struct.pack_into('<HH', buf, 12, 0, 1)
    struct.pack_into('<II', buf, 16, 10, 0x80000000 | 24)
    struct.pack_into('<HH', buf, 24 + 12, n, 0)
    patches = []
    for i, name in enumerate(names):
        encoded = name.encode('utf-16-le')
        noff = len(buf)
        buf += struct.pack('<H', len(encoded) // 2) + encoded
        while len(buf) % 4:
            buf += b'\0'
        loff = len(buf)
        buf += b'\0' * 24
        struct.pack_into('<HHII', buf, loff + 12, 0, 1, 0, loff + 24)
        doff = len(buf)
        buf += b'\0' * 16
        struct.pack_into('<II', buf, 40 + 8 * i, noff | 0x80000000, loff | 0x80000000)
        patches.append((doff, resources[name]))
    for off, value in patches:
        start = len(buf)
        buf += value
        struct.pack_into('<IIII', buf, off, 0x1000 + start, len(value), 0, 0)
        while len(buf) % 4:
            buf += b'\0'
    pe = bytearray(0x200)
    pe[:2] = b'MZ'
    struct.pack_into('<I', pe, 0x3c, 0x80)
    pe[0x80:0x84] = b'PE\0\0'
    opt_size = 240 if plus else 224
    struct.pack_into('<HHIIIHH', pe, 0x84, 0x8664 if plus else 0x14c, 1, 0, 0, 0, opt_size, 2)
    opt = 0x98
    struct.pack_into('<H', pe, opt, 0x20b if plus else 0x10b)
    struct.pack_into('<I', pe, opt + (108 if plus else 92), 16)
    struct.pack_into('<II', pe, opt + (112 if plus else 96) + 16, 0x1000, len(buf))
    sec = opt + opt_size
    pe[sec:sec + 8] = b'.rsrc\0\0\0'
    struct.pack_into('<IIII', pe, sec + 8, len(buf), 0x1000, len(buf), 0x200)
    return bytes(pe + buf)


def payload_resources(filename='VirtualBox-7.2.20-175154-Win.msi', arch=3):
    payload = bytes.fromhex('d0cf11e0a1b11ae1') + b'\0' * 504
    name = b'BIN_00\0'.ljust(28, b'\0')
    filename_bytes = filename.encode('ascii') + b'\0'
    header = struct.pack('<I', arch) + name + filename_bytes.ljust(224, b'\0')
    return {'MANIFEST': b'VBoxInstV1' + b'\0' * 5 + bytes([1]),
            'HDR_00': header, 'BIN_00': payload}
