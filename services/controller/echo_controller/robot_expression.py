"""Deterministic simulation expressions, driven only by fixed output WAVs."""
from array import array
from functools import lru_cache
import math
import sys
import wave


@lru_cache(maxsize=40)
def voice_rhythm(path):
    """50 ms RMS windows from a bundled clip; never microphone input."""
    with wave.open(str(path)) as source:
        rate=source.getframerate()
        samples = array('h', source.readframes(source.getnframes()))
    return rhythm_samples(samples,rate)


def rhythm_pcm(pcm,rate):
    return rhythm_samples(array('h',pcm),rate)


def rhythm_samples(samples,rate):
    size=max(1,int(rate*.05))
    if sys.byteorder != 'little':
        samples.byteswap()
    levels = [math.sqrt(sum(float(x) * x for x in samples[i:i+size]) / len(samples[i:i+size]))
              for i in range(0, len(samples), size)]
    peak = max(levels, default=1) or 1
    return tuple(min(1., level / peak) for level in levels)


def rhythm_at(levels, elapsed):
    index = max(0., elapsed / .05)
    first = int(index)
    if first >= len(levels):
        return 0.
    second = min(first + 1, len(levels) - 1)
    return levels[first] + (levels[second] - levels[first]) * (index - first)


def expression_pose(motion, elapsed, duration=0., voice=0.):
    """Return antenna radians, head XYZ metres and head roll/pitch/yaw radians.

    These larger, deliberately visible poses are simulation-only. The physical
    adapters retain their original measured-baseline antenna profiles.
    """
    t = max(0., elapsed)
    voice = min(1., max(0., voice))
    if motion == 'IDLE':
        right, left = 4 * math.sin(t * .7), 3 * math.sin(t * .7 + .8)
        roll, pitch, yaw, lift = 1.3 * math.sin(t * .45), .8 * math.sin(t * .6), 4 * math.sin(t * .28), 0
    else:
        envelope = min(1., t / .35) * min(1., max(0., duration - t) / .45) if duration else 1.
        beat = math.sin(t * math.tau * 1.1)
        right, left = (4 + 8 * voice) * beat, (4 + 8 * voice) * math.sin(t * math.tau * 1.1 + .5)
        roll, pitch, yaw, lift = 1.5 * math.sin(t * 1.2), 2 * voice * beat, 3 * math.sin(t * .7), 0
        if motion == 'WAVE':
            right += 23 * math.sin(t * math.tau * 1.5)
            left -= 13
            roll += 3 * math.sin(t * math.tau * .75)
        elif motion == 'LISTEN':
            right += 16
            left -= 8
            roll += 4
            yaw += 2 * math.sin(t * .9)
        elif motion == 'NOD':
            pitch += 4 * math.sin(t * math.tau * .85)
            right += 5
            left -= 5
        elif motion == 'POINT':
            left -= 24
            right += 7
            yaw -= 6
            roll -= 3
        elif motion == 'CELEBRATE':
            # Perked antenna fan + quick cheers, small double nod and head lift.
            cheer = math.sin(t * math.tau * 2)
            right, left = 24 + 10 * cheer, -24 - 10 * cheer
            pitch = 4 * math.sin(t * math.tau * 1.2)
            roll = 4 * math.sin(t * math.tau * .8)
            yaw = 3 * math.sin(t * math.tau * .6)
            lift = .005
        right, left, roll, pitch, yaw, lift = [x * envelope for x in (right,left,roll,pitch,yaw,lift)]
    antennas = [math.radians(max(-40., min(40., value))) for value in (right,left)]
    return antennas, [0.,0.,lift], [math.radians(value) for value in (roll,pitch,yaw)]


def approach(current, target, rate, delta):
    limit = rate * max(0., min(.1, delta))
    return [a + max(-limit, min(limit, b-a)) for a,b in zip(current,target)]
