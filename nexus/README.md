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
- `capabilities.result` (for forwarded capabilities response)
- `scene.state` (for scene collect responses)
