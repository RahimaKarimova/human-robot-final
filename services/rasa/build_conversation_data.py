"""Build a fixed Rasa dialogue policy from public intent labels, never replies."""
import json
from pathlib import Path

root=Path(__file__).resolve().parent
phrases=json.loads((root.parent/'protocol/control_phrases.json').read_text())
replies=json.loads((root.parent/'protocol/reply_intents.json').read_text(encoding='utf-8'))
folder=root/'conversation'
folder.mkdir(exist_ok=True)
intents={key.lower():key for key in phrases}
intents['reply_given']='REPLY'
intents['nlu_fallback']='UNKNOWN'
intents['name_given']='NAME_GIVEN'
for key in replies: intents['answer_'+key.lower()]=key
nlu=['version: "3.1"','nlu:']
for intent,examples in phrases.items():
    nlu += [f'- intent: {intent.lower()}','  examples: |']+[f'    - {item}' for item in examples]
non_commands=json.loads((root.parent/'protocol/non_command_examples.json').read_text(encoding='utf-8'))
nlu += ['- intent: reply_given','  examples: |','    - reply supplied']+[f'    - {item}' for item in non_commands]
nlu += ['- intent: name_given','  examples: |','    - my name is Alex','    - you can call me Sam','    - I am Alice','    - call me Robin']
for key,entry in replies.items():
    nlu += ['- intent: answer_'+key.lower(),'  examples: |']+[f'    - {text}' for text in entry['examples']]
(folder/'nlu.yml').write_text('\n'.join(nlu)+'\n')
domain=['version: "3.1"','intents:']+[f'  - {key}' for key in intents]+['responses:']
rules=['version: "3.1"','rules:']
for key,value in intents.items():
    domain += [f'  utter_{key}:',f'    - text: "{value}"']
    rules += [f'- rule: Route {key}','  steps:',f'    - intent: {key}',f'    - action: utter_{key}']
domain += ['session_config:','  session_expiration_time: 30','  carry_over_slots_to_new_session: false']
(folder/'domain.yml').write_text('\n'.join(domain)+'\n')
(folder/'rules.yml').write_text('\n'.join(rules)+'\n')
print('Generated fixed conversational policy; no player utterances used.')
