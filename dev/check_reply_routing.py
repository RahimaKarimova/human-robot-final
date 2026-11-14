"""Synthetic local Rasa plus CPU extractor audit. No microphone."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/controller'))
from echo_controller.conversation import RasaConversation

r=RasaConversation('http://127.0.0.1:5007')
for answer,expected in [('I love science books about black holes.','BOOKS_SCIENCE'),
                        ('I like history books about ancient Egypt.','BOOKS_HISTORY'),
                        ("I don't like reading.",'BOOKS_DISLIKE')]:
    result=r.understand(answer,'G1')
    assert result==expected,(result,expected)
    print(expected,'passed')
for command in ['REPEAT','CLARIFY','WAIT','NO_RECALL','PRIVACY']:
    assert r.decide(command)==command
print('Support routing passed')
