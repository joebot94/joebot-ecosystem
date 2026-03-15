# GlitchBoard Handoff

Last updated: 2026-03-15 (America/New_York)
Repo: `joebot-ecosystem`
App path: `GlitchBoard/`

## Purpose
GlitchBoard is a native SwiftUI macOS DAW-style show control app for Joebot Ecosystem. It loads audio, shows waveform + musical grid, places device cues on lanes, and fires intents via Nexus.

## Run / Build

```bash
cd /Users/joe/Documents/joebot-ecosystem/GlitchBoard
swift run GlitchBoard
```

Release run:

```bash
swift build -c release
open .build/release/GlitchBoard
```

## Current Feature Inventory

### Core transport/audio
- Load audio file with `AVAudioPlayer`
- Play / Pause / Stop
- Current time + total duration display
- BPM editable (used for musical grid calculations)

### Timeline / visualization
- Horizontal zoom (`-`, `+`, `Fit`) synced across ruler, waveform, lanes
- Bar/beat ruler with major bar lines and beat ticks
- Bar labels rendered centered per bar cell
- Waveform rendered in SwiftUI `Canvas`
- Shared playhead overlay across ruler/waveform/lanes
- Dark Joebot styling (grey/orange)

### Cue lanes
- Dynamic lane list (not single hardcoded lane)
- Lane statuses: online/offline/connecting
- Lane accent colors by device type
- Lane-level cue counts + clear buttons
- Lane capability summary text (`source/actions/I-O/model`)

### Cues
- Click lane to place one-shot cue (snap to 1/4 note)
- Drag on lane to create range cue
- Range cues with draggable start/end handles
- Interpolation modes: `linear`, `step`, `triangle`
- Right-click cue context menu: Edit / Mute / Duplicate / Delete
- Delete key removes selected cue
- Cue tooltip with lane/action/params/bar-beat

### Cue editing panel
- Device dropdown (lane target)
- Action dropdown (Nexus/cached/bootstrap supplied)
- Action source indicator: `Nexus`, `Bootstrapped`, `Fallback`
- Typed params:
  - Integer/decimal: slider + numeric entry
  - Boolean: toggle
  - Option enums: dropdown
  - Bitset masks: clickable bit grid for multi I/O
- Range cue start/end param editors

### Multi-input/output control support
- Bootstrap actions include multi-target variants:
  - `set_input_skew_multi` (`input_mask`)
  - `route_tie_multi` (`output_mask`)
  - Dirty mixer multi channel mask placeholder
  - Atlas multi route placeholder
- Dispatch serialization maps params to correct payload types (`Bool`, `Int`, `Double`)

### Nexus integration
- `NexusStatusIndicator` in toolbar
- Manual capability refresh button
- Capability polling toggle button
- Lane/device matching via Nexus registry + discovery hints
- Capability parsing supports multiple response formats

### Capability cache / resilience
- Last-known capabilities cache file:
  - `~/JBT/glitchboard/capabilities_cache.json`
- Cache loaded at startup, used when Nexus/device offline
- Capability metadata summarization (model/action count/input/output hints)

### Persistence
- Save setlist as `.jbt` (`daw_setlist` schema)
- Load `.jbt` setlists
- Legacy project load compatibility path
- Autosave every 60 seconds:
  - `~/JBT/glitchboard/autosave.jbt`
- Recovery prompt on launch if autosave exists

### Performance work already completed
- Playhead updates throttled to ~30 FPS timer
- Playhead rendered as lightweight overlay layer
- Grid rendering separated from animated playhead
- Lane cue filter avoids per-frame resorting
- Dispatch status text updates throttled to reduce redraw churn

## Confirmed Fixes In Latest Pass
- Ruler bar labels are centered per bar segment to avoid 1-digit vs 2-digit drift
- Bottom timestamp now uses direct AVFoundation timing source:
  - left = `AVAudioPlayer.currentTime`
  - right = `AVAudioPlayer.duration`
- BPM remains grid-only and is not used to compute elapsed/total seconds

## Known Issues / Gaps
- Cue scheduling still uses timer-based lookahead dispatch, not sample-accurate `AVAudioTime`
- Waveform still drawn in `Canvas` (not yet prerendered/cached as image texture)
- Cue static layer is not fully texture-cached; still SwiftUI view composition per lane
- No explicit edit mode system yet (Edit/Select/Razor/Cursor placeholders from spec)
- Snap division currently fixed to 1/4 note in UI
- No lane offline behavior controls (`skip/queue/warn`) surfaced yet
- No dedicated performance dashboard mode

## Recommended Next Roadmap Checklist
1. Implement sample-accurate cue scheduling via audio timeline (`AVAudioTime`/engine clock)
2. Pre-render waveform to cached `CGImage` at load time
3. Pre-render static cue layer per lane and keep playhead as separate overlay
4. Add selectable snap divisions (`Off, 1/1, 1/2, 1/4, 1/8, 1/16, 1/32`)
5. Add lane offline behavior UI + queue timeout options
6. Add capability-driven parameter widgets for richer schemas (enum labels, units, step granularity)
7. Add pattern/selection tools (phase 2+ from spec)
8. Add edit mode toolbar (Edit/Select/Razor/Cursor)
9. Build performance diagnostics panel (fps, dropped redraws, scheduling latency)

## Important Files
- `GlitchBoard/Sources/GlitchBoard/Models/GlitchBoardState.swift`
- `GlitchBoard/Sources/GlitchBoard/Views/GlitchBoardMainView.swift`
- `GlitchBoard/Sources/GlitchBoard/Models/CueDefinitions.swift`
- `GlitchBoard/Sources/GlitchBoard/Models/TimelineCue.swift`
- `GlitchBoard/Sources/GlitchBoard/Models/CueLane.swift`

## Recent Commits (GlitchBoard)
- `d963116` perf: reduce playback UI lag and playhead redraw cost
- `33a77ae` multi I/O masks + capability cache + polling controls
- `1f6907e` bootstrap capability-driven cue editing controls

