"""Create independent synthetic DetX data; never reads a private project."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
parser.add_argument('--count', type=int, default=1000)
args = parser.parse_args()
if not 1 <= args.count <= 50_000:
    parser.error('--count must be between 1 and 50000')

def timecode(frame):
    seconds, frames = divmod(frame, 25)
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f'{hours:02}:{minutes:02}:{seconds:02}:{frames:02}'

root = ET.Element('detx')
header = ET.SubElement(root, 'header')
ET.SubElement(header, 'title').text = 'Vérification de charge indépendante'
ET.SubElement(header, 'videofile', timestamp='10:00:00:00')
ET.SubElement(header, 'last_position', timecode='10:00:05:00', track='0')
roles = ET.SubElement(root, 'roles')
ET.SubElement(roles, 'role', id='test', name='Rôle de vérification', color='#000000')
body = ET.SubElement(root, 'body')
origin = 10 * 3600 * 25
for index in range(args.count):
    start = origin + index * 50
    if index % 50 == 0:
        ET.SubElement(body, 'loop', number=str(index // 50 + 1), timecode=timecode(start))
    if index % 25 == 0:
        ET.SubElement(body, 'shot', timecode=timecode(start))
    line = ET.SubElement(body, 'line', role='test', track=str(index % 4))
    ET.SubElement(line, 'lipsync', type='in_open', timecode=timecode(start))
    ET.SubElement(line, 'text').text = f'Réplique {index + 1} : café, é🙂 et synchronisation.'
    ET.SubElement(line, 'lipsync', type='out_open', timecode=timecode(start + 40))
args.output.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(root).write(args.output, encoding='utf-8', xml_declaration=True)
print(f'Synthetic DetX: {args.count} phrases -> {args.output}')
