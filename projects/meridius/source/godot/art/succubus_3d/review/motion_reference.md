# Wing, tail and whip motion reference (23-24 October 2026)

Measured from the videos the user gave (frames sampled and tracked; the videos
themselves are not kept in the repository).

## Wings: https://www.youtube.com/watch?v=dLqI21iT6IY

A keyframed game character in a model viewer (60 fps). Measured at 1:49–1:51 and
1:57–1:59 (walk) and 0:00–0:03, 1:18–1:22 (idle).

- **Walk:** the wings stay folded, wrist claws up by the ears, the membrane hanging to
  hip level; from the front 10–20 % of the wing shows.
  - Step 0.61 s, stride 1.22 s.
  - A bob once per step: about 2.5 degrees at the root, the trailing tips 1.5 times that,
    lowest when the body is lowest; no lag at the tip.
  - A sideways swing once per stride: the folded edge about 9 degrees, opposite to the
    hips' sideways sway.
- **Idle:** half spread, a slow sway with a period of 1.75 s. About 7 degrees at the inner
  edge and 8 at the outer fingertip, the span changing by 3 %. Root and tip peaks are about
  a quarter cycle apart.

## Tail: https://youtu.be/-zImukzI5Rc?t=276

An animatronic tail on a dress form: no walking.

- The wag (4:30–4:36): period 1.00 s, about +-30–35 degrees at the tip.
- The base turns as much as the tip: a stiff rod with no wave travelling down it.
- At rest it hangs down and back, 40–45 degrees from vertical. While wagging, the outer
  half lifts 15–20 degrees and the tip curls up.
- The app moves the tail on every second step (once per stride).

## Whip: https://www.youtube.com/watch?v=ASK_NEQ3C8Y

A 2.5 s line animation (24 fps, no audio) of an arm cracking a tapered whip; all 59 frames
looked at (24 October).

- 0.21–0.33 s: the arm lifts; the lash trails below the hand.
- 0.38–0.58 s: wind-up; the lash is dragged up and back over.
- 0.63–0.75 s: forward stroke; the lash lies in a long arc behind and above the hand
  (loaded).
- 0.79–0.83 s: the arm stops at the target. A narrow loop forms: the part by the hand runs
  straight along the strike line, turns, and the rest folds back. The loop rolls out to
  the tip.
- 0.88–0.92 s: the lash snaps straight along the arm's line: the crack.
- 0.96–1.00 s: it recoils in an S-wave.
- 1.04–1.17 s: it droops, and hangs straight down by about 1.3 s.

`tools/whip_motion.py` follows these phases for each of the attack's two strikes (see the
README's The whip).

## As used in `tools/secondary_motion.py`

| | Value |
| --- | --- |
| Tail period | Once per stride, 1.2 s (about 20 % slower than the reference, as asked) |
| Tail swing per bone | 9, 8, 7, 6, 5 and 4 degrees x 1.3 when walking; tip about +-22 degrees, 0.38 m |
| Tail lag per bone | 22 degrees (not in the reference; it makes the tail flow) |
| Tail carriage | 45 degrees back from vertical; the last three bones curl up 6 degrees each |
| Wings | Walk folded; idle 45 % of the way from spread to folded, with a sway over the 1.83 s loop |
