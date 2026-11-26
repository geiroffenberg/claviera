Piano preview samples: Meta Piano, an upright piano recorded by Meta's Creative
Audio team.
License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
Original library: https://github.com/facebookincubator/Meta-open-sound
(systems/instruments/meta-piano), velocity layer 3 (mf).

For Claviera one sample was kept for every third note (MIDI 21, 24, ..., 108),
resampled to 44.1 kHz mono, with leading silence removed, truncated to four
seconds and faded out over the last 0.3 seconds. The 120 sample was derived by
speeding up the 108 sample by an octave. Roots from 84 up were low-passed
(2-pole, 7 kHz) to soften the tone. Each root was gain-adjusted so its first
second measures about -28 LUFS (EBU R128), keeping peaks below -3 dBFS, and
re-encoded as AAC at 96 kbit/s. Playback shifts the nearest root by at most
one or two semitones.
