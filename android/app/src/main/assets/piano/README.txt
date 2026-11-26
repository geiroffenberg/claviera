Piano preview samples: Meta Piano, an upright piano recorded by Meta's Creative
Audio team.
License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
Original library: https://github.com/facebookincubator/Meta-open-sound
Revision: 514c926efecdb3c7812bf00eedf8e5c8d61dd681
Source: systems/instruments/meta-piano/ogg, velocity layer 3 (mf).

For Claviera one sample was kept for every third note (MIDI 21, 24, ..., 108),
resampled to 44.1 kHz mono, with leading silence removed, truncated to four
seconds and faded out over the last 0.3 seconds. The 120 sample was derived by
speeding up the 108 sample by an octave. To reduce noticeable dips between
neighbouring notes, roots 27, 60 and 102 were boosted by 3 dB; 57 by 5 dB;
81, 84 and 99 by 4 dB; and 87 by 2 dB. Other roots retain their original
levels. No low-pass filter or reverb was added to the samples; they are
re-encoded as AAC at 96 kbit/s. Playback shifts the nearest root, including
larger shifts outside the sampled piano range.
