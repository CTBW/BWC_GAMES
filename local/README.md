# Local-only material

Git ignores everything in this folder except this README. It holds material
that must not reach the public remote:

- `audio-library/`: the Meridius sound library (Sonniss, Freesound, Kenney,
  OpenGameArt). The Sonniss licence forbids redistribution. Licences and
  sources are in `audio-library/LICENSES.md`.
  `projects/meridius/source/godot/tools/audio/build_bank.py` renders the game's
  sound bank from it; `MERIDIUS_AUDIO_LIBRARY` overrides the path.
- `ability-icons/`: the owner's 2048 px ability paintings, the source of the
  painted icons made by `projects/meridius/source/godot/tools/ui_key_icons.py`.

GitHub has no copy of this folder. Back it up separately.
