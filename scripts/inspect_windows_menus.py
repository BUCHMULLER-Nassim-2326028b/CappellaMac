"""Extrait les menus PE Windows sans charger ni exécuter le programme.

Usage : python scripts/inspect_windows_menus.py assets/Cappella.exe
"""
import argparse
import json
from pathlib import Path
import struct


def inspect(path):
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 60)[0]
    if data[:2] != b'MZ' or data[pe:pe+4] != b'PE\0\0':
        raise ValueError('Exécutable PE attendu')
    count = struct.unpack_from('<H', data, pe+6)[0]
    optional_size = struct.unpack_from('<H', data, pe+20)[0]
    optional = pe+24
    magic = struct.unpack_from('<H', data, optional)[0]
    directories = optional+(96 if magic == 0x10b else 112)
    sections = []
    for index in range(count):
        pos = optional+optional_size+40*index
        virtual_size, address, raw_size, raw_pos = struct.unpack_from('<IIII', data, pos+8)
        sections.append((address, max(virtual_size, raw_size), raw_pos))

    def offset(address):
        for start, size, pos in sections:
            if start <= address < start+size:
                return pos+address-start
        raise ValueError('Adresse PE hors sections')

    resource_address = struct.unpack_from('<I', data, directories+16)[0]
    base = offset(resource_address)

    def walk(relative, path=()):
        pos = base+relative
        named, ids = struct.unpack_from('<HH', data, pos+12)
        for index in range(named+ids):
            key, child = struct.unpack_from('<II', data, pos+16+8*index)
            if child & 0x80000000:
                yield from walk(child & 0x7fffffff, path+(key,))
            else:
                address, size, _, _ = struct.unpack_from('<IIII', data, base+child)
                yield path+(key,), data[offset(address):offset(address)+size]

    menus = []
    for resource_path, resource in walk(0):
        if resource_path[0] != 4:
            continue
        version, header_size = struct.unpack_from('<HH', resource)
        if version != 0:
            raise ValueError('Format MENUEX non pris en charge')

        def items(pos, depth=0):
            while pos < len(resource):
                flags = struct.unpack_from('<H', resource, pos)[0]
                pos += 2
                command = None
                if not flags & 16:
                    command = struct.unpack_from('<H', resource, pos)[0]
                    pos += 2
                end = pos
                while resource[end:end+2] != b'\0\0':
                    if end >= len(resource):
                        raise ValueError('Libellé de menu tronqué')
                    end += 2
                label = resource[pos:end].decode('utf-16-le')
                pos = end+2
                if label:
                    menus.append(dict(resource=resource_path[1], depth=depth, id=command, label=label))
                if flags & 16:
                    pos = items(pos, depth+1)
                if flags & 128:
                    break
            return pos

        items(4+header_size)
    return menus


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.path), ensure_ascii=False, indent=2))
