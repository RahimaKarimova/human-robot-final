"""Expand the Rasa conversation training data with many natural ways people answer.

Merges hand-written, varied examples (short, casual, hesitant, long, UK/US
spelling, specific titles/places) into services/protocol/reply_intents.json and
writes "not a command" look-alikes to services/protocol/non_command_examples.json.
Existing examples are kept; duplicates are skipped. Re-run safely at any time:

    services/controller/.venv/Scripts/python.exe dev/expand_rasa_training.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPLIES = ROOT / "services/protocol/reply_intents.json"
NON_COMMANDS_PATH = ROOT / "services/protocol/non_command_examples.json"

ANSWERS = {
    # G1: What kind of stories or books do you enjoy?
    "BOOKS_FANTASY": [
        "fantasy", "fantasy books", "fantasy mostly", "um fantasy I think", "definitely fantasy",
        "I'm really into fantasy", "anything with magic", "books with magic and dragons", "dragons",
        "stories with dragons and wizards", "Harry Potter", "I love Harry Potter", "the Harry Potter books",
        "Lord of the Rings", "I like The Hobbit", "Narnia", "Percy Jackson", "fairy tales",
        "I like fairy tales and myths", "magical worlds", "epic fantasy", "books about elves and magic",
        "I read a lot of fantasy novels", "my favourite is fantasy", "my favorite genre is fantasy",
        "stories about magic schools", "anything with wizards in it", "I like mythology stories",
        "Greek myths", "high fantasy with big battles", "books set in magical kingdoms",
        "I like stories where people have magic powers", "fantasy and fairy tales", "Game of Thrones",
        "I enjoy books like Eragon", "witches and wizards", "I like reading about mythical creatures",
    ],
    "BOOKS_MYSTERY": [
        "mystery", "mysteries", "mystery books", "detective stories", "crime novels", "I like crime fiction",
        "whodunits", "I love a good whodunit", "Sherlock Holmes", "Agatha Christie", "I read Agatha Christie",
        "murder mysteries", "thrillers", "psychological thrillers", "I like thrillers and mysteries",
        "stories where you solve a crime", "books with a twist at the end", "I like guessing who did it",
        "detective novels", "I'm into true crime", "spy stories", "spy thrillers", "suspense books",
        "anything with a mystery to solve", "I enjoy puzzles in stories", "Nancy Drew",
        "I like the Hardy Boys", "crime and detective stuff", "um mystery stuff I guess",
        "books with clues and secrets", "I love solving mysteries in books", "police procedurals",
        "I like reading about detectives", "mystery and suspense mostly",
    ],
    "BOOKS_ADVENTURE": [
        "adventure", "adventure stories", "adventure books", "action and adventure", "action books",
        "pirate stories", "stories about pirates", "Treasure Island", "treasure hunts", "survival stories",
        "books about explorers", "exploring and quests", "quest stories", "jungle adventures",
        "stories about travelling the world", "Indiana Jones type stories", "Robinson Crusoe",
        "I like stories where they go on a journey", "journeys and expeditions", "shipwreck stories",
        "books about climbing mountains", "action packed books", "I love an adventure",
        "anything with a big adventure", "stories about lost cities", "I like stories set at sea",
        "adventure and exploring", "Jules Verne", "Around the World in Eighty Days",
        "I like stories about kids going on adventures", "Hatchet", "the Famous Five",
        "survival and exploration books",
    ],
    "BOOKS_SCIENCE": [
        "science", "science books", "science fiction", "sci-fi", "sci fi", "scifi", "space stories",
        "books about space", "astronomy", "books about the universe", "black holes", "physics books",
        "popular science", "I like reading about how things work", "books about technology",
        "robots", "stories about robots", "books about robots and AI", "artificial intelligence",
        "biology books", "books about animals and nature", "nature and wildlife books", "dinosaurs",
        "books about dinosaurs", "chemistry", "inventions and inventors", "Star Wars books",
        "The Martian", "Isaac Asimov", "I like Stephen Hawking", "A Brief History of Time",
        "books about the human body", "medicine and science", "futuristic stories", "time travel stories",
        "aliens", "stories about aliens", "dystopian sci-fi", "I like learning facts from books",
        "non-fiction about science", "space exploration and planets",
    ],
    "BOOKS_HISTORY": [
        "history", "history books", "historical fiction", "historical novels", "books about the past",
        "ancient Egypt", "ancient Rome", "ancient Greece", "the Romans", "Vikings", "books about Vikings",
        "World War Two", "World War 2 books", "war stories", "books about the world wars",
        "medieval history", "knights and castles", "the Tudors", "biographies", "autobiographies",
        "memoirs", "true stories", "books about real people", "books about famous people",
        "the history of kings and queens", "pharaohs and pyramids", "the Middle Ages", "samurai",
        "Anne Frank", "the Titanic", "history and politics", "I like learning about old civilizations",
        "I like real events from the past", "the Cold War", "the Aztecs", "historical biographies",
    ],
    "BOOKS_LIKE": [
        "all kinds", "all sorts of books", "a bit of everything", "anything really", "pretty much anything",
        "I read everything", "I like most books", "I love reading", "I'm a big reader", "I read a lot",
        "lots of different genres", "any good story", "a mix of things", "whatever looks interesting",
        "novels", "I like novels", "comics", "graphic novels", "manga", "I read manga",
        "comic books", "poetry", "romance", "romance novels", "funny books", "comedy books",
        "horror", "horror stories", "scary stories", "classics", "classic novels", "short stories",
        "young adult books", "I like YA novels", "children's books", "audiobooks", "I listen to audiobooks",
        "books with happy endings", "stories about friendship", "drama", "I like realistic fiction",
        "depends on my mood", "it depends really", "I don't have a favourite, I like lots",
    ],
    "BOOKS_DISLIKE": [
        "I don't read", "I don't really read", "I don't read much", "not really a reader",
        "I'm not much of a reader", "I don't like reading", "reading is boring", "books are boring",
        "I find reading boring", "I hate reading", "I never read", "I haven't read a book in years",
        "I prefer films", "I'd rather watch movies", "I prefer watching TV", "I'd rather play video games",
        "I prefer games to books", "I only read for school", "only when I have to", "I don't have time to read",
        "I don't enjoy books", "books aren't my thing", "reading isn't for me", "not books really",
        "I'm not into books", "I struggle to finish books", "I get bored reading", "I watch shows instead",
        "I prefer podcasts", "none really", "not really any",
    ],
    # G2: Do you like exploring new places, or do you prefer somewhere familiar?
    "EXPLORE_NEW": [
        "new places", "exploring", "I love exploring", "definitely new places", "somewhere new",
        "I like going somewhere new", "I love travelling", "I love to travel", "I like adventure",
        "I like discovering new things", "new places for sure", "I always want to see new places",
        "exploring new cities", "I like trying new things", "I get bored in the same place",
        "I love visiting new countries", "the unknown is exciting", "I prefer exploring",
        "new definitely", "I like road trips to new places", "backpacking", "I like hiking new trails",
        "I love seeing the world", "travelling abroad", "I like going off the beaten path",
        "I like surprises when I travel", "somewhere I've never been", "exploring for sure",
        "new and exciting places", "I'd pick the new place", "I'm curious so new places",
    ],
    "PREFER_FAMILIAR": [
        "familiar", "familiar places", "somewhere familiar", "somewhere I know", "I like home",
        "home", "I prefer staying home", "I'm a homebody", "I like my comfort zone", "the familiar one",
        "places I already know", "I like routine", "I prefer what I know", "I don't like change",
        "I get nervous in new places", "new places make me anxious", "I like my usual spots",
        "my favourite cafe", "same places every time", "I like going back to the same holiday place",
        "I feel safer somewhere familiar", "I'm more of a stay at home person", "familiar for sure",
        "I prefer cozy familiar places", "I prefer cosy familiar places", "my own neighbourhood",
        "I like knowing where I'm going", "familiar definitely", "I don't really like travelling",
        "travelling stresses me out", "I prefer somewhere I'm comfortable",
    ],
    # G3: If you could explore any place in a story, where would you go?
    "PLACE_FANTASY": [
        "Hogwarts", "I'd go to Hogwarts", "Narnia", "Middle Earth", "the Shire", "Rivendell",
        "Wonderland", "Alice in Wonderland", "Neverland", "Oz", "the Land of Oz", "a magical kingdom",
        "a castle with dragons", "a dragon's lair", "an enchanted forest", "a fairy kingdom",
        "Atlantis", "a city in the clouds", "a floating island", "Westeros", "Camp Half-Blood",
        "the Chocolate Factory", "Willy Wonka's factory", "Mount Olympus", "Asgard", "Pandora",
        "a wizard school", "a land with unicorns", "somewhere with magic", "the Upside Down",
        "a magical library", "Diagon Alley", "Hyrule", "Studio Ghibli worlds", "Spirited Away's bathhouse",
    ],
    "PLACE_ADVENTURE": [
        "a treasure island", "a desert island", "a pirate ship", "the jungle", "the Amazon rainforest",
        "a lost city", "El Dorado", "the pyramids", "inside a pyramid", "an ancient temple", "a hidden cave",
        "the bottom of the ocean", "under the sea", "a shipwreck", "the Arctic", "Antarctica", "the North Pole",
        "Mount Everest", "the top of a mountain", "a volcano", "the Wild West", "the Sahara", "a safari",
        "outer space", "the Moon", "Mars", "a spaceship", "the centre of the earth", "Jurassic Park",
        "Skull Island", "a deep jungle temple", "Machu Picchu", "the Lost World", "a rainforest expedition",
        "a mysterious island", "the Bermuda Triangle",
    ],
    # P1: What's something you often put off doing?
    "PUT_OFF_STUDY": [
        "homework", "my homework", "studying", "revision", "revising", "revising for exams",
        "studying for tests", "assignments", "my assignments", "essays", "writing essays", "my essay",
        "coursework", "my dissertation", "my thesis", "reading for class", "school work", "uni work",
        "university work", "college work", "maths homework", "project work", "group projects",
        "practising piano", "practising my instrument", "learning vocabulary", "language practice",
        "applying for jobs", "job applications", "emails for school", "reading my notes",
        "I always leave homework to the last minute", "I procrastinate on assignments",
        "starting my essays", "preparing presentations",
    ],
    "PUT_OFF_CHORES": [
        "chores", "housework", "cleaning", "cleaning my room", "tidying up", "tidying my room",
        "the dishes", "washing up", "doing the dishes", "laundry", "the laundry", "folding clothes",
        "ironing", "vacuuming", "hoovering", "taking out the bins", "taking out the trash",
        "making my bed", "grocery shopping", "food shopping", "cooking", "cooking dinner",
        "paperwork", "paying bills", "replying to messages", "answering emails", "calling people back",
        "going to the dentist", "doctor appointments", "booking appointments", "exercise", "going to the gym",
        "going to bed early", "getting up early", "sorting my wardrobe", "decluttering", "admin stuff",
    ],
    # P2: What's something you find difficult or uncomfortable?
    "SOCIAL_DIFFICULTY": [
        "talking to people", "talking to strangers", "meeting new people", "making friends",
        "small talk", "making small talk", "public speaking", "speaking in public", "presentations",
        "giving presentations", "speaking in class", "asking questions in class", "parties",
        "big groups", "crowds", "phone calls", "making phone calls", "calling people on the phone",
        "asking for help", "saying no", "saying no to people", "starting conversations",
        "eye contact", "being the centre of attention", "talking to teachers", "talking to my boss",
        "networking", "job interviews", "interviews", "meeting my partner's family", "dating",
        "I'm shy", "I get shy around new people", "social situations", "standing up for myself",
        "telling people how I feel", "confrontation", "arguments", "ordering food at restaurants",
    ],
    "LEARNING_DIFFICULTY": [
        "maths", "math", "mathematics", "algebra", "physics", "chemistry", "statistics", "coding",
        "programming", "learning languages", "learning a new language", "grammar", "spelling",
        "reading quickly", "concentrating", "focusing", "staying focused", "paying attention",
        "remembering things", "memorising things", "remembering names", "exams", "tests",
        "writing essays", "understanding new topics", "learning new software", "technology",
        "using computers", "time management", "organising myself", "getting organised",
        "planning ahead", "maps and directions", "reading maps", "following instructions",
        "music theory", "drawing", "sports", "cooking", "driving", "parking",
    ],
    # P3: What's something you've been worrying about lately?
    "WORRY_STUDY": [
        "exams", "my exams", "upcoming exams", "final exams", "tests", "my grades", "grades",
        "my marks", "failing", "failing a class", "school", "uni", "university", "college",
        "my dissertation", "my thesis", "deadlines", "assignments", "my coursework", "my results",
        "getting into university", "university applications", "my GCSEs", "my A levels", "SATs",
        "my presentation next week", "keeping up with classes", "falling behind at school",
        "homework piling up", "too much schoolwork", "group project", "my teacher", "graduating",
    ],
    "WORRY_FUTURE": [
        "the future", "my future", "what to do after school", "getting a job", "finding a job",
        "my career", "career choices", "work", "my job", "losing my job", "job interviews",
        "money", "money stuff", "finances", "paying rent", "bills", "saving money", "moving out",
        "moving house", "moving to a new city", "growing up", "becoming an adult", "what I want to do",
        "climate change", "the environment", "the economy", "getting older", "my health",
        "my family", "my parents", "a family member being ill", "my friends", "friendships",
        "relationships", "my relationship", "the news", "the world", "everything really",
    ],
}

# Look-alikes that must NOT become commands (negations, past tense, answers that
# share a command word). Trained as "reply_given" = a normal reply.
NON_COMMANDS = [
    "don't skip the question", "do not skip", "please don't skip it", "no don't skip",
    "please do not stop", "don't stop", "don't stop the game", "no keep going don't stop",
    "I stopped reading that book", "I stopped reading years ago", "I never stop reading",
    "I can't stop reading fantasy", "don't pause", "no need to pause", "please don't pause the game",
    "don't repeat it", "no need to repeat", "you don't need to repeat that", "I don't need a hint",
    "no hints please", "I need help with my family", "I help my family a lot",
    "I skip breakfast sometimes", "I skipped class once", "I put off taking a break",
    "I take breaks too often", "I keep repeating the same mistakes", "I worry I repeat myself",
    "I wait until the last minute", "I hate waiting", "waiting in queues", "I record music",
    "my privacy online", "yes", "yeah", "no", "no, not really", "ok", "okay", "sure", "maybe",
    "hmm", "I think so", "not sure yet but I like stories", "that's a good question",
]


def merge(existing, new):
    seen = {item.casefold() for item in existing}
    added = [item for item in new if item.casefold() not in seen and not seen.add(item.casefold())]
    return existing + added, len(added)


def main():
    replies = json.loads(REPLIES.read_text(encoding="utf-8"))
    for label, examples in ANSWERS.items():
        replies[label]["examples"], count = merge(replies[label]["examples"], examples)
        print(f"{label:20s} +{count:3d} -> {len(replies[label]['examples'])}")
    REPLIES.write_text(json.dumps(replies, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    NON_COMMANDS_PATH.write_text(json.dumps(NON_COMMANDS_LIST, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"non-command look-alikes: {len(NON_COMMANDS_LIST)}")


NON_COMMANDS_LIST = NON_COMMANDS

if __name__ == "__main__":
    main()
