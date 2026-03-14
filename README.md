# Joebot Ecosystem 🦖🟢🟢🟢

Monorepo for tonight's build session:

- `nexus/` - Python asyncio websocket coordination server on port `8675`
- `JoebotSDK/` - shared Swift package (`NexusClient`, `NexusStatusIndicator`, protocol models)
- `DirtyMixerApp/` - SwiftUI app wired to Nexus as `dirtymixer_v1`
- `GlitchCatalogSwift/` - SwiftUI shell wired to Nexus as `glitch_catalog`
- `Observatory/` - SwiftUI monitor wired to Nexus as `observatory`

## Quick Start

1. Start Nexus:

```bash
cd nexus
python3 -m pip install -r requirements.txt
python3 main.py
```

2. In separate terminals run apps:

```bash
cd DirtyMixerApp && swift run
cd GlitchCatalogSwift && swift run
cd Observatory && swift run
```

3. Optional protocol check:

```bash
cd nexus
python3 test_client.py
```

## One-Command Local Run

From repo root:

```bash
./scripts/joebot-stack.sh up
```

For normal desktop use (opens 4 Terminal tabs and launches all apps):

```bash
./scripts/open-stack-tabs.sh
```

Useful commands:

```bash
./scripts/joebot-stack.sh status
./scripts/joebot-stack.sh logs
./scripts/joebot-stack.sh down
```

## Current Scope

Implemented for this milestone:

- Websocket envelope + core message types
- Client registry + heartbeat timeout/offline detection
- Monitor broadcasts (`client.status`, `client.state`, `registry.snapshot`)
- DirtyMixer state updates on parameter changes
- Glitch Catalog Snapshot -> `scene_save`
- Observatory live cards for online/offline clients

Not yet implemented (deliberately out of scope tonight):

- Full `.jbt` production file system and migration tooling
- Scene management UX
- Extron adapters
