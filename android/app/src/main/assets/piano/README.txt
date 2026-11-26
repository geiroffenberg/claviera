Piano preview samples: Steinway B, Versilian Community Sample Library (VCSL).
License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
Original library: https://github.com/sgossner/VCSL
Source: https://github.com/StanislavMakhnytskyi/stapiano-samples
Revision: 49685600cd66448c637a25be08d6041ce620f065
Source folder: steinway-b, medium-velocity (v2) samples, MIDI roots 22, 34, 46,
58, 70, 82, 94, 104. The source recordings were trimmed, gain-adjusted and
encoded as described in the source repository's README and LICENSE.

For Claviera the samples were truncated to three seconds, faded out over the
last 0.2 seconds and re-encoded as mono AAC. The 116 and 127 samples were
derived by speeding up the 104 sample, first by an octave and then by
approximately 11 semitones, respectively. To soften the tone, each root was
low-passed (2-pole; 7 kHz up to root 82, 5.5 kHz for 94 and 104, 4.5 kHz for 116
and 127), then gain-adjusted so its first second measures about -28 LUFS
(EBU R128; -30 for 94 and 104, -32 for 116 and 127), keeping peaks below
-3 dBFS, and re-encoded at 96 kbit/s. Playback shifts the nearest root.
The reduced set is intended only as a lightweight prototype.
