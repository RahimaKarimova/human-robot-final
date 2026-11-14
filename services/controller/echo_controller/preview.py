"""Fixed complete companion rehearsal. No generated dialogue or participant answers."""
import json
from pathlib import Path
from .reply_understanding import REPLIES

ROOT = Path(__file__).resolve().parents[3]
DRAFT = json.loads((ROOT / "services/protocol/draft_dialogue.json").read_text(encoding="utf-8-sig"))
GAME = json.loads((ROOT / "data/game.json").read_text(encoding="utf-8-sig"))
ADDITIONS = json.loads((ROOT / "services/protocol/companion_preview.json").read_text(encoding="utf-8"))["lines"]
RECORDED_EXPRESSIVE = json.loads((ROOT/'assets/audio/manifest.json').read_text(encoding='utf-8-sig')).get('companion_welcome',{}).get('voice','').startswith('qwen3-tts-')
QUESTIONS = set(DRAFT["questions"]) | {"NAME"}
STAGES = {stage["id"]: stage for stage in GAME["stages"]}
SUCCESS = {stage: stage.upper() + "_SUCCESS" for stage in STAGES if stage != "cave"}
LINE_IDS = QUESTIONS | set(ADDITIONS) | set(DRAFT["condition_overrides"]) | {key + "_ACK" for key in DRAFT["questions"]} | {"ENDING"}
CONVERSATION_NOTICES = {
    'WAITING': "Take your time. You can answer when you're ready, or say skip.",
    'DEVELOPMENT_PRIVACY': 'Your speech is processed locally. This development game does not save audio or answer transcripts. You can skip any question.',
    'REPAIR': "I didn't quite catch that. You can try again, say repeat, or say skip."
}


def conversation_notice(notice_id):
    return dict(text=CONVERSATION_NOTICES[notice_id],audio_id='companion_notice_'+notice_id.lower(),
                motion_id='NOD',question=False,provenance='proposed_shared_conversation_support')


def schedule(stage, phase, condition='humour'):
    if phase == "welcome":
        return ["WELCOME"]
    if phase == "ending":
        return ["ENDING"]
    lines = []
    for key in STAGES[stage].get(phase, []):
        if condition=='control' and key in DRAFT['condition_overrides']:
            continue
        lines.append(key)
        if key in QUESTIONS:
            lines.append(key + "_ACK")
    if phase == "after":
        lines.append(SUCCESS[stage])
    return lines


def script(line_id, condition, skipped=False,reply_kind='DEFAULT',nickname='',reply_text=''):
    if reply_text and not skipped and line_id.endswith('_ACK') and line_id[:-4] in DRAFT['questions']:
        return dict(text=reply_text,audio_id='companion_ack',speech_text=reply_text,generated_reply=True,motion_id='NOD',question=False,provenance='offline_cpu_contextual_reply')
    if nickname and line_id in {'NAME_ACK','LIBRARY_SUCCESS','TEMPLE_SUCCESS','ENDING'}:
        if RECORDED_EXPRESSIVE:
            base=script(line_id,condition,skipped,reply_kind)
            text=nickname+'! '+base['text']
            return {**base,'text':text,'speech_text':text,'provenance':'session_name_with_recorded_expressive_voice'}
        templates={
            'NAME_ACK':"Lovely to meet you, {name}! Let's head to the Forest Library and meet Elara.",
            'LIBRARY_SUCCESS':"Great work, {name}! You found the emerald. That's our first precious gem for the cave door!",
            'TEMPLE_SUCCESS':"Brilliant, {name}! All four gems are ours. Let's put them into the sealed cave door.",
            'ENDING':"We found it, {name}! That was great teamwork. Thanks for exploring Echo Island with me!"
        }
        text=templates[line_id].format(name=nickname)
        return dict(text=text,audio_id='companion_'+line_id.lower(),speech_text=text,motion_id='WAVE' if line_id=='NAME_ACK' else 'CELEBRATE',
                    question=False,provenance='session_personalised_greeting')
    if not skipped and line_id.endswith('_ACK') and reply_kind in REPLIES and line_id[:-4] in REPLIES[reply_kind]['questions']:
        return reply_response(reply_kind)
    if line_id in ADDITIONS:
        text, motion = ADDITIONS[line_id]["text"], ADDITIONS[line_id]["motion_id"]
        return dict(text=text, audio_id="companion_" + line_id.lower(), motion_id=motion,
                    question=line_id == "NAME", provenance="proposed_development_addition")
    if line_id.endswith("_ACK") and line_id[:-4] in DRAFT["questions"]:
        text = GAME["skip_acknowledgement" if skipped else "acknowledgement"]
        suffix = "skip" if skipped else "ack"
        return dict(text=text, audio_id="companion_" + suffix, motion_id="NOD", question=False,
                    provenance="supplied_shared_acknowledgement")
    if line_id in DRAFT["questions"]:
        lead_in=DRAFT.get('question_lead_ins',{}).get(line_id,'')
        text=' '.join(part for part in (lead_in,DRAFT['questions'][line_id]) if part)
        return dict(text=text, audio_id="companion_" + line_id.lower(), motion_id="LISTEN",
                    question=True, provenance="user_requested_reciprocal_question_intro" if lead_in else "supplied_execution_plan_v2")
    if line_id in DRAFT["condition_overrides"]:
        return dict(text=DRAFT["condition_overrides"][line_id][condition],
                    audio_id="companion_" + line_id.lower() + "_" + condition, motion_id="NOD", question=False,
                    provenance="user_requested_contextual_joke_revision")
    if line_id == "ENDING":
        return dict(text=GAME["ending"], audio_id="companion_ending", motion_id="CELEBRATE", question=False,
                    provenance="supplied_shared_ending")
    raise ValueError("Unsupported preview line.")


def hint(level, stage="library"):
    prefix = "" if stage == "library" else stage + "_"
    return dict(text=STAGES[stage]["hints"][level - 1], audio_id=f"companion_{prefix}hint_{level}",
                motion_id="POINT", question=False, provenance="shared_game_hint")


def all_clips():
    entries = [script(key, "control") for key in ADDITIONS]
    entries += [script(key, "control") for key in DRAFT["questions"]]
    entries += [script("G1_ACK", "control", skipped) for skipped in (False, True)]
    entries += [script(key, condition) for key in DRAFT["condition_overrides"] for condition in ("control", "humour")]
    entries += [hint(level, stage) for stage in SUCCESS for level in (1, 2, 3)]
    entries.append(script("ENDING", "control"))
    entries += [conversation_notice(key) for key in CONVERSATION_NOTICES]
    entries += [reply_response(key) for key in REPLIES]
    return entries


def reply_response(kind):
    entry=REPLIES[kind]
    return dict(text=entry['response'],audio_id='companion_reply_'+kind.lower(),motion_id=entry['motion'],
                question=False,provenance='proposed_contextual_reply')
