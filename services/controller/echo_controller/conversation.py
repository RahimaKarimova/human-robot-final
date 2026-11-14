"""Local stateless answer classification; Core receives fixed intent markers only."""
import uuid
from .companion_gateway import exchange, local_url
from .reply_understanding import REPLIES,book_negation

INTENTS={'REPLY','STOP','PAUSE','RESUME','SKIP','REPEAT','HINT','WAIT','NO_RECALL','CLARIFY','PRIVACY','UNKNOWN'}
INTENTS |= set(REPLIES)|{'NAME_GIVEN'}


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
        intent=result.get('intent',{})
        label=str(intent.get('name','')).removeprefix('answer_').upper()
        ranking=result.get('intent_ranking',[])
        runner_up=ranking[1].get('confidence',0) if len(ranking)>1 else 0
        if (label in REPLIES and question in REPLIES[label]['questions']
                and intent.get('confidence',0)>=.65 and intent.get('confidence',0)-runner_up>=.15):
            return self.decide(label)
        self.decide('REPLY')
        return 'DEFAULT'
