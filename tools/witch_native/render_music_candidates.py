#!/usr/bin/env python3
"""Original, deterministic score/synthesis candidates; no external recordings.

Outputs loopable stereo PCM and an inspectable event score. Signal validation
does not constitute musical/listening approval.
"""
from pathlib import Path
import argparse, hashlib, json, math, wave
import numpy as np

RATE = 44100
BEATS = 64
CHORDS = [(50, 57, 60, 64), (55, 59, 62, 69), (48, 55, 59, 64), (53, 57, 60, 67),
          (50, 57, 60, 65), (52, 55, 59, 62), (55, 59, 62, 67), (50, 57, 60, 64)]
# Dorian phrases, rests between answers; independently authored for this project.
MELODY = [[(0,74,1.5), (2,77,.5), (3,76,1)], [(1,74,1), (2.5,69,1)],
          [(0,72,1), (1.5,71,.5), (3,67,1)], [(0,69,2), (3,72,.5)],
          [(.5,74,1), (2,77,1)], [(0,76,1.5), (2,74,1)],
          [(0,71,1), (1.5,69,.5), (3,67,1)], [(0,69,2), (3,74,.75)]]

def render(track, out):
    bpm = {'home':80, 'field':84, 'battle':108}[track]
    beat = 60 / bpm
    length = round(BEATS * beat * RATE)
    mix = np.zeros((length, 2), dtype=np.float64)
    events = []
    def add(at, note, beats, gain, kind='pluck', pan=0.):
        events.append({'beat':at,'midi':note,'beats':beats,'gain':gain,'instrument':kind,'pan':pan})
        duration = beats * beat
        release = .28 if kind=='pluck' else .7
        n = round((duration+release)*RATE)
        t = np.arange(n)/RATE
        freq = 440 * 2**((note-69)/12)
        phase = 2*np.pi*freq*t
        if kind=='pluck':
            env = (1-np.exp(-t/.008))*np.exp(-t/(.23+duration*.3))
            signal = np.sin(phase)+.22*np.sin(2*phase)*np.exp(-t/.12)+.075*np.sin(3*phase)*np.exp(-t/.08)
        elif kind=='pad':
            env = np.minimum(1,t/.24)*np.minimum(1,np.maximum(0,duration+release-t)/release)
            signal = .68*np.sin(phase)+.18*np.sin(phase*1.0018)+.09*np.sin(2*phase)
        else:
            env = (1-np.exp(-t/.018))*np.exp(-t/(duration*.62))
            signal = np.sin(phase)+.13*np.sin(2*phase)
        # Tail reaches exact zero before wrapping; no hard sample cutoff.
        env *= np.minimum(1,np.maximum(0,duration+release-t)/.08)
        signal *= env*gain
        idx = (round(at*beat*RATE)+np.arange(n)) % length
        gains = [math.cos((pan+1)*math.pi/4),math.sin((pan+1)*math.pi/4)]
        for c,g in enumerate(gains): np.add.at(mix[:,c],idx,signal*g)
    for bar in range(16):
        chord = CHORDS[bar%8]; start = bar*4
        for i,note in enumerate(chord):
            add(start,note,3.7,.026 if track!='battle' else .023,'pad',[-.5,-.15,.2,.55][i])
        add(start,chord[0]-12,2.7,.075,'bass',-.06)
        if track=='battle': add(start+2,chord[0]-12,1.55,.065,'bass',.06)
        offsets = [0,1,2,3] if track=='home' else [0,.75,1.5,2,2.75,3.5]
        if track=='battle': offsets=[i*.5 for i in range(8)]
        for j,offset in enumerate(offsets):
            add(start+offset,chord[(j+bar%2)%4]+12,.65,.043 if track!='battle' else .05,'pluck',-.35 if j%2 else .35)
        for offset,note,duration in MELODY[bar%8]:
            if bar>=8 and bar%4==3: note+=12
            add(start+offset,note,duration,.068 if track!='battle' else .08,'pluck',.12)
    # Circular, low-level room taps preserve a continuous loop boundary.
    dry=mix.copy()
    for delay,gain in [(.113,.14),(.227,.07),(.347,.035)]:
        mix += np.roll(dry,round(delay*RATE),axis=0)[:,::-1]*gain
    mix -= mix.mean(axis=0)
    peak=float(np.max(np.abs(mix)))
    mix *= .56/peak
    pcm=np.round(mix*32767).astype('<i2')
    path=out/(track+'_r001.wav')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    adjacent=np.abs(np.diff(pcm.astype(np.int32),axis=0));seam=np.abs(pcm[0].astype(np.int32)-pcm[-1].astype(np.int32))
    info={'id':track,'file':path.name,'bpm':bpm,'beats':BEATS,'bars':16,'sampleRate':RATE,'channels':2,
          'frames':length,'durationSeconds':length/RATE,'peak':float(np.max(np.abs(pcm.astype(np.int32)))/32767),
          'rmsDBFS':float(20*np.log10(np.sqrt(np.mean((pcm.astype(np.float64)/32767)**2)))),
          'clippedSamples':int(np.sum(np.abs(pcm.astype(np.int32))>=32767)),
          'loopSeamDeltaPCM':seam.tolist(),'interiorP999DeltaPCM':float(np.quantile(adjacent,.999)),
          'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'scoreEvents':events}
    assert info['clippedSamples']==0 and np.max(seam)<=max(3,info['interiorP999DeltaPCM'])
    return info

def main():
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    tracks=[render(t,args.output) for t in ['home','field','battle']]
    manifest={'schema':'witch.music.candidate.v1','status':'UNAPPROVED_TEST_OVERLAY','humanApproval':False,
              'provenance':'Original note events and deterministic local synthesis; no external audio, samples or reference melody.',
              'scope':'Three functional scene cues; not a commercial soundtrack catalog or sale-product decision.',
              'quality':'Signal checks only. Musical quality and physical-device listening are unverified.',
              'generatorSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'tracks':tracks}
    (args.output/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps([{k:v for k,v in t.items() if k!='scoreEvents'} for t in tracks],indent=2))

if __name__=='__main__':main()
