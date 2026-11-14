"""Bounded planned-answer intents and session nickname extraction."""
import json
import re
from pathlib import Path

REPLIES=json.loads((Path(__file__).resolve().parents[2]/'protocol/reply_intents.json').read_text(encoding='utf-8'))
REPLY_KINDS=set(REPLIES)|{'DEFAULT','NAME_GIVEN'}


def extract_nickname(text):
    text=text.strip().strip('.!?').replace('’',"'")
    text=re.sub(r"^(?:my name is|you can call me|please call me|call me|i am|i'm|it is|it's)\s+",'',text,flags=re.I)
    if not 1<=len(text)<=32 or not 1<=len(text.split())<=3:
        return ''
    if not all(char.isalpha() or char in " '-" for char in text):
        return ''
    if set(text.lower().split()) & {'yes','no','skip','stop','repeat','nothing','hello','know','like','enjoy','books','dont','don\'t','think','thanks'}:
        return ''
    return text.title()


def book_negation(text):
    text=text.casefold().replace('’',"'")
    negative=bool(re.search(r"(?:don'?t|do not|never|not|hate|dislike|can'?t stand).{0,28}(?:books?|reading|read\b)",text))
    mixed=bool(re.search(r"\bbut\b|\bexcept\b|\balthough\b",text))
    return negative and not mixed
