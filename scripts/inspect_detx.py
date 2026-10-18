"""Audit structurel en lecture seule ; ne copie pas le contenu des dialogues.

Usage : python scripts/inspect_detx.py fichier.detx --fps 25
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def inspect(path, fps):
    data = path.read_bytes()
    if len(data) >= 50_000_000 or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("Taille ou déclaration XML non prise en charge")
    root = ET.fromstring(data)
    if root.tag != "detx":
        raise ValueError("Racine différente de detx")

    def frame(value):
        parts = value.split(":")
        if len(parts) != 4 or not all(p.isascii() and p.isdecimal() for p in parts):
            raise ValueError(f"Timecode invalide : {value}")
        h, m, s, f = map(int, parts)
        if h > 999 or m >= 60 or s >= 60 or f >= fps:
            raise ValueError(f"Timecode incompatible avec {fps} i/s : {value}")
        return ((h * 60 + m) * 60 + s) * fps + f

    roles = root.findall("./roles/role")
    role_ids = [r.get("id") for r in roles]
    if None in role_ids or len(set(role_ids)) != len(role_ids):
        raise ValueError("Identifiants de rôles invalides")
    video = root.find("./header/videofile")
    origin = frame(video.get("timestamp", "00:00:00:00")) if video is not None else 0
    lines = root.findall("./body/line")
    shapes = Counter()
    for line in lines:
        if line.get("role") not in role_ids:
            raise ValueError("Référence de rôle absente")
        track = int(line.get("track", "-1"))
        if not 0 <= track <= 15:
            raise ValueError("Piste non prise en charge")
        shapes[" / ".join(child.tag for child in line)] += 1
        if [child.tag for child in line] != ["lipsync", "text", "lipsync"] or len(line[1]):
            raise ValueError("Profil de phrase plus riche que celui actuellement implémenté")
        if frame(line[2].get("timecode", "")) <= frame(line[0].get("timecode", "")):
            raise ValueError("Fin de phrase antérieure au début")
    for element in root.iter():
        if "timecode" in element.attrib:
            frame(element.get("timecode"))
    return {
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "cappella_version": root.find("./header/cappella").get("version"),
        "fps_assumed_not_declared": fps,
        "media_start_frame": origin,
        "counts": dict(Counter(e.tag for e in root.iter())),
        "tracks": dict(Counter(line.get("track") for line in lines)),
        "line_shapes": dict(shapes),
        "lipsync_types": dict(Counter(e.get("type") for e in root.iter("lipsync"))),
        "structure_matches_implemented_profile": True,
        "native_swift_roundtrip_verified": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--fps", type=int, choices=(24, 25, 30), default=25)
    arguments = parser.parse_args()
    print(json.dumps(inspect(arguments.path, arguments.fps), ensure_ascii=False, indent=2))
