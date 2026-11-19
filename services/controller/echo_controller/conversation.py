"""Local stateless answer classification; Core receives fixed intent markers only."""
import uuid
from .companion_gateway import exchange, local_url
from .reply_understanding import REPLIES,book_negation

INTENTS={'REPLY','STOP','PAUSE','RESUME','SKIP','REPEAT','HINT','WAIT','NO_RECALL','CLARIFY','PRIVACY','UNKNOWN'}
INTENTS |= set(REPLIES)|{'NAME_GIVEN'}


def pick_answer(ranking, question, minimum_share=.65, minimum_margin=.15, minimum_on_topic=.5):
    """Choose an answer category among those that fit the question just asked.

    The same words can answer different questions ("Narnia" is a fantasy book for
    G1 and a fantasy place for G3), so only this question's categories compete.
    The answer must be mostly about them (on-topic share), and one must clearly
    lead; otherwise the caller falls back to the grounded free-text reply.
    """
    scores = {}
    for entry in ranking:
        label = str(entry.get('name', '')).removeprefix('answer_').upper()
        if label in REPLIES and question in REPLIES[label]['questions']:
            scores[label] = float(entry.get('confidence', 0) or 0)
    on_topic = sum(scores.values())
    if not scores or on_topic < minimum_on_topic:
        return None
    ordered = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    best, best_score = ordered[0]
    runner_up = ordered[1][1] if len(ordered) > 1 else 0.
    if best_score / on_topic >= minimum_share and (best_score - runner_up) / on_topic >= minimum_margin:
        return best
    return None


class RasaConversation:
    def __init__(self,url='http://127.0.0.1:5006',sender=None):
        self.url=local_url(url)
        self.sender=sender or 'echo-'+uuid.uuid4().hex

    def decide(self,intent):
        if intent not in INTENTS:
            raise ValueError('Unsupported conversation intent.')
        label='reply_given' if intent=='REPLY' else 'nlu_fallback' if intent=='UNKNOWN' else 'answer_'+intent.lower() if intent in REPLIES else intent.lower()
        replies=exchange(self.url+'/webhooks/rest/webhook',{'sender':self.sender,'message':'/'+label})
        if not isinstance(replies,list) or len(replies)!=1 or replies[0].get('text')!=intent:
            raise ValueError('Conversation policy response did not match the fixed protocol.')
        return intent

    def understand(self,text,question):
        if question=='G1' and book_negation(text):
            return self.decide('BOOKS_DISLIKE')
        result=exchange(self.url+'/model/parse',{'text':text[:400]})
        label=pick_answer(result.get('intent_ranking',[]),question)
        if label:
            return self.decide(label)
        self.decide('REPLY')
        return 'DEFAULT'
