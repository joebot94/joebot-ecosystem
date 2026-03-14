# Nexus 🦖

Nexus is the central websocket coordinator for the Joebot Ecosystem.

## Run

```bash
cd nexus
python3 -m pip install -r requirements.txt
python3 main.py
```

Expected startup log includes `🦖` and listens on port `8675`.

## Quick Test

```bash
cd nexus
python3 test_client.py
```

## Message Envelope

```json
{
  "id": "msg_001",
  "type": "message_type",
  "source": "client_id",
  "payload": {}
}
```

## Implemented Message Types

- `register`
- `heartbeat`
- `state_update`
- `query`
- `intent`
- `capabilities.query`
- `scene_save`
- `scene_recall`
- `recording.start`
- `recording.stop`
- `recording.request`
- `capabilities.result` (for forwarded capabilities response)
- `scene.state` (for scene collect responses)

## Recording + Event Logs

- Session IDs are provided by clients (for example, Glitch Catalog) and Nexus uses those IDs as-is.
- Every active recording appends events in-memory and writes a backup JSON log to:
  - `~/.nexus/logs/<session_id>_<YYYYMMDD>_<HHMMSS>.json`
- `recording.request` returns the full session event log payload so clients can embed it in `.jbt`.
- Replay scaffolding exists in `core/event_recorder.py` with base timestamp timing and speed multipliers:
  - `0.5x`, `1x` (default), `2x`, `4x`
