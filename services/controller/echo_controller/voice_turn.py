"""Offline WebRTC utterance endpointing. No input device or transcription here.

Prepared for optional conversational listening; importing this module never
opens a microphone or enables automatic capture in an existing session.
"""
from collections import deque

SAMPLE_RATE = 16000
FRAME_MS = 20
FRAME_BYTES = SAMPLE_RATE * FRAME_MS // 1000 * 2


class VoiceTurn:
    def __init__(self, end_silence_ms=1000, max_speech_seconds=30, classifier=None):
        if not 400 <= end_silence_ms <= 2500 or not 2 <= max_speech_seconds <= 60:
            raise ValueError('Unsupported voice-turn timing.')
        if classifier is None:
            import webrtcvad
            vad = webrtcvad.Vad(2)
            classifier = lambda frame: vad.is_speech(frame, SAMPLE_RATE)
        self.classifier = classifier
        self.end_frames = end_silence_ms // FRAME_MS
        self.max_frames = int(max_speech_seconds * 1000 / FRAME_MS)
        self.reset()

    def reset(self):
        self.pending = bytearray()
        self.pre_roll = deque(maxlen=15)  # Preserve 300 ms before detected onset.
        self.onset = deque(maxlen=5)
        self.audio = bytearray()
        self.state = 'waiting'
        self.voiced = self.trailing = self.frames = 0

    def discard(self):
        self.reset()
        self.state = 'discarded'

    def feed(self, pcm):
        if self.state not in {'waiting', 'speaking'}:
            return self.state  # One turn cannot complete twice.
        self.pending.extend(pcm)
        while len(self.pending) >= FRAME_BYTES:
            frame = bytes(self.pending[:FRAME_BYTES])
            del self.pending[:FRAME_BYTES]
            speech = bool(self.classifier(frame))
            if self.state == 'waiting':
                self.pre_roll.append(frame)
                self.onset.append(speech)
                if sum(self.onset) < 3:
                    continue
                self.state = 'speaking'
                self.audio.extend(b''.join(self.pre_roll))
                self.pre_roll.clear()
                self.voiced = sum(self.onset)
                self.frames = len(self.audio) // FRAME_BYTES
                continue
            self.audio.extend(frame)
            self.frames += 1
            self.voiced += speech
            self.trailing = 0 if speech else self.trailing + 1
            if self.trailing >= self.end_frames:
                if self.voiced >= 8:  # Reject very brief clicks/noise bursts.
                    self.state = 'complete'
                    self.pending.clear()
                    return self.state
                self.reset()
                return self.state
            if self.frames >= self.max_frames:
                self.discard()
                self.state = 'too_long'
                return self.state  # Never submit a truncated answer.
        return self.state

    def take(self):
        if self.state != 'complete':
            raise RuntimeError('No complete spoken turn is available.')
        pcm = bytes(self.audio)
        self.discard()
        self.state = 'consumed'
        return pcm
