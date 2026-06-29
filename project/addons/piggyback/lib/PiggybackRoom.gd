## Abstract class that defines the shared logic between protocols
@abstract
class_name PiggybackRoom extends WebRTCMultiplayerPeer
const Utils := preload("./Utils.gd")
const TrackerConnection := preload("../tracker/TrackerConnection.gd")
const NostrConnection := preload("../nostr/NostrConnection.gd")
const PiggybackPeer := preload("../PiggybackPeer.gd")

enum State { NEW, STARTED }

## The mode of this room. In mesh networks, no single peer gets authority.
## In server/client mode, the server gets a network id of 1 granting it authority over all other peers.
enum Mode { MESH, CLIENT, SERVER }

## The protocol to exchange offers/answer over. Currently only webtorrent trackers and nostr relays are supported.
enum Protocol { TRACKER, NOSTR }


class RoomConfig:
	var offer_pool_size: int ## The population of the offer peer pool. Defaults to 40.
	var offer_timeout: int ## The ttl for an offer peer. Defaults to 120.
	var identifier: String ## The human readable identifier for this room. Defaults to "com.piggyback.default"
	var protocol: Protocol # Which protocol to use. Defaults to Nostr.
	var socket_urls: Array[String] ## An array of websocket urls to connect to. Defaults to the list defined in NostrConnection
	var room_id: String ## How this room is identified over the network. Defaults to a sha1 of the config.identifier.
	var room_mode: Mode ## See Mode
	var auto_start: bool ## Start the offer exchange on initialization. Defaults to true.

	func _init(config = {}):
		offer_pool_size = config.get("offer_pool_size", 40)
		offer_timeout = config.get("offer_timeout", 120)
		identifier = config.get("identifer", "com.piggyback.default")
		protocol = config.get("protocol", Protocol.NOSTR)
		socket_urls = NostrConnection.DEFAULT_RELAY_URLS if protocol == Protocol.NOSTR else TrackerConnection.DEFAULT_TRACKER_URLS
		room_mode = config.get("room_mode", Mode.MESH)
		auto_start = config.get("auto_start", true)
		room_id = config.get("room_id", identifier.sha1_text().substr(0, 20))

signal peer_joined(rpc_id: int, peer: PiggybackPeer) # Emitted when a peer joined the room
signal peer_left(rpc_id: int, peer: PiggybackPeer) # Emitted when a peer left the room

var _config: RoomConfig

var _state := State.NEW # Internal state
var _peer_id := Utils.gen_id()
var _connections: Array[PiggybackConnection] = [] # A list of connections used to share/get offers/answers
var _connected_peers = {}

var rpc_id:
	get: return get_unique_id()
var peer_id:
	get: return _peer_id
var type:
	get: return _config.room_mode
var id:
	get: return _config.room_id
var connected_peers:
	get: return _connected_peers.values()
var peers:
	get: return get_peers().values().map(func(v): return v.connection)

var is_mesh:
	get: return _config.room_mode == Mode.MESH
var is_client:
	get: return _config.room_mode == Mode.CLIENT
var is_server:
	get: return _config.room_mode == Mode.SERVER

static func _create_room(config:={}) -> PiggybackRoom:
	match config.get("protocol", Protocol.NOSTR):
		Protocol.NOSTR:
			return NostrRoom.new(config)
		Protocol.TRACKER:
			return TrackerRoom.new(config)
		_:
			return NostrRoom.new(config)

static func create_mesh_room(config:={}) -> PiggybackRoom:
	config.room_mode = PiggybackRoom.Mode.MESH
	return _create_room(config)

static func create_server_room(config:={}) -> PiggybackRoom:
	config.room_mode = PiggybackRoom.Mode.SERVER
	return _create_room(config)

static func create_client_room(room_id: String, config:={}) -> PiggybackRoom:
	config.room_mode = PiggybackRoom.Mode.CLIENT
	config.room_id = room_id
	return _create_room(config)

func _init(config:= {}):
	_config = RoomConfig.new(config)

	peer_connected.connect(self._on_peer_connected)
	peer_disconnected.connect(self._on_peer_disconnected)

	if _config.auto_start:
		start()

func start() -> Error:
	if _state != State.NEW:
		push_error("Already started")
		return Error.ERR_ALREADY_IN_USE

	_state = State.STARTED

	match _config.room_mode:
		Mode.MESH:
			var err := create_mesh(generate_unique_id())
			if err != OK:
				push_error("Creating mesh failed")
				return err
		Mode.CLIENT:
			var err := create_client(generate_unique_id())
			if err != OK:
				push_error("Creating client failed")
				return err
		Mode.SERVER:
			_config.room_id = _peer_id # Our room_id should be our peer_id to identify ourself as the server
			var err := create_server()
			if err != OK:
				push_error("Creating server failed")
				return err
		_:
			push_error("Invalid type")
			return Error.ERR_INVALID_DATA

	for url in _config.socket_urls:
		_connections.append(_create_connection(url))

	Engine.get_main_loop().process_frame.connect(self.__poll)
	return Error.OK

@abstract
func _create_connection(url: String) -> PiggybackConnection

func find_peers(filter:={}) -> Array[PiggybackPeer]:
	var result: Array[PiggybackPeer] = []
	for peer in peers:
		var matched := true
		for key in filter:
			if not key in peer or peer[key] != filter[key]:
				matched = false
				break
		if matched:
			result.append(peer)
	return result

func find_peer(filter:={}, allow_multiple_results:=false) -> PiggybackPeer:
	var matches := find_peers(filter)
	if not allow_multiple_results and matches.size() > 1: return null
	if matches.size() == 0: return null
	return matches[0]

# Broadcast an event to everybody in this room or just specific peers. (List of peer_id)
func send_event(event_name: String, event_args:=[], target_peer_ids:=[]):
	for peer: PiggybackPeer in peers:
		if not peer.is_connected: continue
		if target_peer_ids.size() > 0 and not target_peer_ids.has(peer.id): continue
		peer.send_event(event_name, event_args)

@abstract
func _on_poll()

func __poll():
	poll()
	_on_poll()

@abstract
func _on_got_offer(offer: PiggybackConnection.Response, tracker_client: PiggybackConnection) -> void

@abstract
func _on_got_answer(answer: PiggybackConnection.Response, client: PiggybackConnection) -> void


func _remove_unanswered_offer(offer_id: String) -> void:
	var offer := find_peer({ "answered": false, "offer_id": offer_id })
	if offer != null:
		offer.close()

func _create_offer() -> PiggybackPeer:
	if is_client and has_peer(1): return # We already created the host offer. So lets ignore the offer creating

	var offer_peer := PiggybackPeer.create_offer_peer()
	var offer_rpc_id := 1 if is_client else generate_unique_id()
	add_peer(offer_peer, offer_rpc_id)

	if offer_peer.start() == OK:
		# Cleanup when the offer was not answered for long time
		Engine.get_main_loop().create_timer(_config.offer_timeout).timeout.connect(self._remove_unanswered_offer.bind(offer_peer.offer_id))
		return offer_peer
	else:
		remove_peer(offer_rpc_id)
		return null

func _send_answer_sdp(_type: String, answer_sdp: String, peer: PiggybackPeer, client: PiggybackConnection):
	client.answer(_config.room_id, peer.id, peer.offer_id, answer_sdp)

func _on_failure(reason: String, client: PiggybackConnection) -> void:
	print("Client failure: ", reason, ", Url: ", client.tracker_url)

func _on_peer_connected(rpc_id: int):
	var peer: PiggybackPeer = get_peer(rpc_id).connection
	_connected_peers[rpc_id] = peer
	peer_joined.emit(rpc_id, peer)

func _on_peer_disconnected(rpc_id: int):
	var peer: PiggybackPeer = _connected_peers[rpc_id]
	_connected_peers.erase(rpc_id)
	peer_left.emit(rpc_id, peer)
