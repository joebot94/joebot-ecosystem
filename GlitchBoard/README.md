# GlitchBoard

Phase 1 prototype for a native SwiftUI macOS DAW-style show control app in the Joebot Ecosystem.

## Features in this phase

- Load audio with `AVFoundation`
- Render waveform in SwiftUI `Canvas`
- Bar/beat ruler synchronized with waveform
- One hardcoded cue lane (`Dirty Mixer`) with click-to-place one-shot cues
- Cue placement snaps to a 1/4 note grid (quarter-note snap)
- Cues fire a Nexus intent when the playhead crosses them
- Joebot Classic dark/orange styling
- `NexusStatusIndicator` in toolbar

## Run

```bash
swift run GlitchBoard
```
