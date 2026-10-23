"""Bounds-checked PE32/PE32+ Oracle-compatible RCDATA reader. Never loads executable code.

Format reference: Microsoft PE/COFF specification. This deliberately supports
only the three-level resource tree needed by the Oracle installer protocol.
"""
from __future__ import annotations
import struct


class PEError(ValueError):
    pass


def read_rcdata(data: bytes) -> dict[str, memoryview]:
    view = memoryview(data)

    def take(offset, size):
        if offset < 0 or size < 0 or offset + size > len(view):
            raise PEError('PE range lies outside file')
        return view[offset:offset + size]

    def unpack(fmt, offset):
        return struct.unpack(fmt, take(offset, struct.calcsize(fmt)))

    if bytes(take(0, 2)) != b'MZ':
        raise PEError('Not a DOS/PE image')
    pe, = unpack('<I', 0x3c)
    if pe < 64 or bytes(take(pe, 4)) != b'PE\0\0':
        raise PEError('Invalid PE signature')
    sections, = unpack('<H', pe + 6)
    opt_size, = unpack('<H', pe + 20)
    opt = pe + 24
    take(opt, opt_size)
    magic, = unpack('<H', opt)
    if magic not in (0x10b, 0x20b) or not 1 <= sections <= 96:
        raise PEError('Unsupported PE header')
    directories = 96 if magic == 0x10b else 112
    if opt_size < directories + 24:
        raise PEError('Truncated data directories')
    count, = unpack('<I', opt + directories - 4)
    if count < 3:
        raise PEError('No resource directory')
    resource_rva, resource_size = unpack('<II', opt + directories + 16)
    if resource_rva == 0 or resource_size < 16:
        raise PEError('Empty resource directory')
    section_table = opt + opt_size
    take(section_table, sections * 40)
    ranges = []
    for index in range(sections):
        _, rva, raw_size, raw_offset = unpack('<IIII', section_table + index * 40 + 8)
        if raw_size:
            take(raw_offset, raw_size)
            if raw_offset < section_table + sections * 40:
                raise PEError('Section overlaps headers')
            ranges.append((rva, raw_size, raw_offset))

    def resolve(rva, size):
        found = [raw + rva - base for base, length, raw in ranges
                 if base <= rva and rva + size <= base + length]
        if len(found) != 1:
            raise PEError('Unmapped or ambiguous resource RVA')
        return found[0]

    resource_offset = resolve(resource_rva, resource_size)
    seen_directories = set()
    budget = 4096

    def relative(offset, size):
        if offset < 0 or offset + size > resource_size:
            raise PEError('Resource structure outside directory')
        return take(resource_offset + offset, size)

    def entries(offset):
        nonlocal budget
        if offset in seen_directories:
            raise PEError('Cyclic or shared resource directory')
        seen_directories.add(offset)
        named, ids = struct.unpack('<HH', relative(offset + 12, 4))
        amount = named + ids
        budget -= amount
        if budget < 0:
            raise PEError('Resource entry budget exceeded')
        table = relative(offset + 16, amount * 8)
        result = []
        keys = set()
        for index in range(amount):
            key, value = struct.unpack_from('<II', table, index * 8)
            if key & 0x80000000:
                position = key & 0x7fffffff
                length, = struct.unpack('<H', relative(position, 2))
                if length > 256:
                    raise PEError('Resource name too long')
                try:
                    key = bytes(relative(position + 2, length * 2)).decode('utf-16-le')
                except UnicodeError as exc:
                    raise PEError('Invalid resource name') from exc
            if key in keys:
                raise PEError('Duplicate resource key')
            keys.add(key)
            result.append((key, value))
        return result

    by_language = {0: {}, 0x0409: {}}
    for kind, child in entries(0):
        if kind != 10:
            continue
        if not child & 0x80000000:
            raise PEError('RCDATA type does not point to a directory')
        for name, languages in entries(child & 0x7fffffff):
            if not isinstance(name, str) or not languages & 0x80000000:
                raise PEError('Unsupported RCDATA name/directory')
            for language, leaf in entries(languages & 0x7fffffff):
                if leaf & 0x80000000:
                    raise PEError('Resource nesting exceeds three levels')
                rva, size, _, _ = struct.unpack('<IIII', relative(leaf, 16))
                payload = take(resolve(rva, size), size)
                if not isinstance(language, int) or not 0 <= language <= 0xffff:
                    raise PEError('Invalid RCDATA language identifier')
                if language in by_language:
                    by_language[language][name] = payload
    neutral, english = by_language[0], by_language[0x0409]
    # Oracle VBoxStubBld writes all MANIFEST/HDR/BIN entries with en-US
    # (0x0409). Keep neutral-only fixtures/older wrappers supported, but never
    # combine package parts from different languages or silently prefer a
    # conflicting second manifest. Identical complete copies are unambiguous.
    if neutral and english and neutral != english:
        raise PEError('Conflicting or mixed neutral/en-US RCDATA resources')
    output = english or neutral
    if not output:
        raise PEError('No supported neutral/en-US RCDATA resources')
    return output
