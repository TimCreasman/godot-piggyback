# godot-piggyback

> Serverless WebRTC matchmaking for Godot - perfect as a "set-and-forget" solution for game jams.

![godot-piggyback logo](assets/icon.svg)

This package signals peers by **piggybacking** off existing distributed networks, requiring no dedicated matchmaking server. It defaults to [Nostr](https://nostr.com/) relays, with [WebTorrent](https://webtorrent.io/) tracker support as well.

---

## Attribution

Forked from [freehuntx/godot-matcha](https://github.com/freehuntx/godot-matcha/tree/master), which was itself inspired by the JavaScript library [Trystero](https://github.com/dmotz/trystero). Huge thanks to both projects and their developers.

This fork adds support for Nostr relays, which tend to be more reliable and plentiful than WebTorrent trackers.

---

## Installation

1. Copy everything under `addons/` into your Godot project.
2. **Non-browser builds only:** install the [webrtc-native](https://github.com/godotengine/webrtc-native) plugin.
3. That's it - you're ready to go!

---

## Usage

Example scenes are available under `project/examples`.

### Mesh Example

All peers connect to each other in a fully-connected mesh topology.

```gdscript
extends Node

var mp1 := PiggybackRoom.create_mesh_room({ "identifier": "my-unique-game-identifier" })
var mp2 := PiggybackRoom.create_mesh_room({ "identifier": "my-unique-game-identifier" })

func _init():
    mp1.peer_joined.connect(func(_id, peer):
        print("(1) Peer connected: ", peer.peer_id)
    )
    mp1.peer_left.connect(func(_id, peer):
        print("(1) Peer disconnected: ", peer.peer_id)
    )
    mp2.peer_joined.connect(func(_id, peer):
        print("(2) Peer connected: ", peer.peer_id)
    )
    mp2.peer_left.connect(func(_id, peer):
        print("(2) Peer disconnected: ", peer.peer_id)
    )
```

### Server / Client Example

One peer acts as the host; others join by room ID.

```gdscript
extends Node

var server := PiggybackRoom.create_server_room()
var client := PiggybackRoom.create_client_room(server.room_id) # Client must know the room ID

func _init():
    server.peer_joined.connect(func(_id, peer):
        print("(server) Peer connected: ", peer.peer_id)
    )
    server.peer_left.connect(func(_id, peer):
        print("(server) Peer disconnected: ", peer.peer_id)
    )
    client.peer_joined.connect(func(_id, peer):
        print("(client) Peer connected: ", peer.peer_id)
    )
    client.peer_left.connect(func(_id, peer):
        print("(client) Peer disconnected: ", peer.peer_id)
    )
```
