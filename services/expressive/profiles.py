"""Authored performance directions; never inferred from personal disclosure scores."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
CONFIG=json.loads(Path(__file__).with_name('delivery_profiles.json').read_text(encoding='utf-8'))


def performance(audio_id):
    if audio_id in {'companion_h1_humour','companion_h2_humour','companion_h3_humour','companion_h4_humour'}:
        role='playful'
    elif audio_id.endswith('_control'):
        role='neutral'
    elif 'success' in audio_id or audio_id=='companion_ending':
        role='celebrate'
    elif audio_id in {'companion_name','companion_g1','companion_g2','companion_g3','companion_p1','companion_p2','companion_p3'}:
        role='curious'
    elif any(word in audio_id for word in ('worry','difficulty','privacy','repair','skip','waiting')):
        role='gentle'
    else:
        role='warm'
    return role,CONFIG['profiles'][role]
