@abstract
class_name PiggybackRoom extends WebRTCMultiplayerPeer
const Utils := preload("./Utils.gd")
const TrackerClient := preload("../tracker/TrackerClient.gd")
const NostrClient := preload("../nostr/NostrClient.gd")
const MatchaPeer := preload("../MatchaPeer.gd")

enum State { NEW, STARTED }
enum RoomType { MESH, CLIENT, SERVER }

class RoomConfig:
	var offer_pool_size: int # The number of offer peers to populate the pool with
	var offer_timeout: int # The ttl for an offer peer
	var identifier: String #
	var protocol: PiggybackClient.Protocol #
	var socket_urls: Array[String]
	var room_id: String # If unset,
	var room_type: RoomType #
	var auto_start: bool #

	func _init(config = {}):

		offer_pool_size = config.get("offer_pool_size", 10)
		offer_timeout = config.get("offer_timeout", 120)
		identifier = config.get("identifer", "com.piggyback.default")
		protocol = config.get("protocol", PiggybackClient.Protocol.NOSTR)
		socket_urls = NostrClient.DEFAULT_RELAY_URLS if protocol == PiggybackClient.Protocol.NOSTR else TrackerClient.DEFAULT_TRACKER_URLS
		room_type = config.get("room_type", RoomType.MESH)
		auto_start = config.get("auto_start", true)
		room_id = config.get("room_id", identifier.sha1_text().substr(0, 20))

signal peer_joined(rpc_id: int, peer: MatchaPeer) # Emitted when a peer joined the room
signal peer_left(rpc_id: int, peer: MatchaPeer) # Emitted when a peer left the room

var _config: RoomConfig

var _state := State.NEW # Internal state
var _peer_id := Utils.gen_id()
var _clients: Array[PiggybackClient] = [] # A list of relay clients we use to share/get offers/answers
var _connected_peers = {}

var rpc_id:
	get: return get_unique_id()
var peer_id:
	get: return _peer_id
var type:
	get: return _config.room_type
var id:
	get: return _config.room_id
var connected_peers:
	get: return _connected_peers.values()
var peers:
	get: return get_peers().values().map(func(v): return v.connection)

var is_mesh:
	get: return _config.room_type == RoomType.MESH
var is_client:
	get: return _config.room_type == RoomType.CLIENT
var is_server:
	get: return _config.room_type == RoomType.SERVER

static func _create_room(config:={}) -> PiggybackRoom:
	match config.get("protocol", PiggybackClient.Protocol.NOSTR):
		PiggybackClient.Protocol.NOSTR:
			return NostrRoom.new(config)
		PiggybackClient.Protocol.TRACKER:
			return TrackerRoom.new(config)
		_:
			return NostrRoom.new(config)

static func create_mesh_room(config:={}) -> PiggybackRoom:
	config.type = "mesh"
	return _create_room(config)

static func create_server_room(config:={}) -> PiggybackRoom:
	config.type = "server"
	return _create_room(config)

static func create_client_room(room_id: String, options:={}) -> PiggybackRoom:
	options.type = "client"
	options.room_id = room_id
	return _create_room(options)

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

	match _config.room_type:
		RoomType.MESH:
			var err := create_mesh(generate_unique_id())
			if err != OK:
				push_error("Creating mesh failed")
				return err
		RoomType.CLIENT:
			var err := create_client(generate_unique_id())
			if err != OK:
				push_error("Creating client failed")
				return err
		RoomType.SERVER:
			_config.identifier = _peer_id # Our room_id should be our peer_id to identify ourself as the server
			var err := create_server()
			if err != OK:
				push_error("Creating server failed")
				return err
		_:
			push_error("Invalid type")
			return Error.ERR_INVALID_DATA

	# Create the tracker_clients based on the urls
	for url in _config.socket_urls:
		_clients.append(_create_client(url))

	Engine.get_main_loop().process_frame.connect(self.__poll)
	return Error.OK

@abstract
func _create_client(url: String) -> PiggybackClient

func find_peers(filter:={}) -> Array[MatchaPeer]:
	var result: Array[MatchaPeer] = []
	for peer in peers:
		var matched := true
		for key in filter:
			if not key in peer or peer[key] != filter[key]:
				matched = false
				break
		if matched:
			result.append(peer)
	return result

func find_peer(filter:={}, allow_multiple_results:=false) -> MatchaPeer:
	var matches := find_peers(filter)
	if not allow_multiple_results and matches.size() > 1: return null
	if matches.size() == 0: return null
	return matches[0]

# Broadcast an event to everybody in this room or just specific peers. (List of peer_id)
func send_event(event_name: String, event_args:=[], target_peer_ids:=[]):
	for peer: MatchaPeer in peers:
		if not peer.is_connected: continue
		if target_peer_ids.size() > 0 and not target_peer_ids.has(peer.id): continue
		peer.send_event(event_name, event_args)

@abstract
func _on_poll()

func __poll():
	poll()
	_on_poll()

func _remove_unanswered_offer(offer_id: String) -> void:
	var offer := find_peer({ "answered": false, "offer_id": offer_id })
	if offer != null:
		offer.close()

func _create_offer() -> MatchaPeer:
	if is_client and has_peer(1): return # We already created the host offer. So lets ignore the offer creating

	var offer_peer := MatchaPeer.create_offer_peer()
	var offer_rpc_id := 1 if is_client else generate_unique_id()
	add_peer(offer_peer, offer_rpc_id)

	if offer_peer.start() == OK:
		# Cleanup when the offer was not answered for long time
		Engine.get_main_loop().create_timer(_config.offer_timeout).timeout.connect(self._remove_unanswered_offer.bind(offer_peer.offer_id))
		return offer_peer
	else:
		remove_peer(offer_rpc_id)
		return null

func _send_answer_sdp(_type: String, answer_sdp: String, peer: MatchaPeer, client: PiggybackClient):
	client.answer(_config.room_id, peer.id, peer.offer_id, answer_sdp)

@abstract
func _handle_offer(offer: PiggybackClient.Response, tracker_client: PiggybackClient)

func _on_got_offer(offer: PiggybackClient.Response, tracker_client: PiggybackClient) -> void:
	if offer.info_hash != _config.room_id: return
	if is_client and offer.peer_id != _config.room_id: return # Ignore offers from others than host (in client mode)

	# Pass processing on to the protocol specific logic
	_handle_offer(offer, tracker_client)

@abstract
func _handle_answer(answer: PiggybackClient.Response, tracker_client: PiggybackClient)

func _on_got_answer(answer: PiggybackClient.Response, client: PiggybackClient) -> void:
	if answer.info_hash != _config.room_id: return
	if is_client and answer.peer_id != _config.room_id: return # As client we just accept answers from the host

	# Pass processing on to the protocol specific logic
	_handle_answer(answer, client)

func _on_failure(reason: String, client: PiggybackClient) -> void:
	print("Client failure: ", reason, ", Url: ", client.tracker_url)

func _on_peer_connected(rpc_id: int):
	var peer: MatchaPeer = get_peer(rpc_id).connection
	_connected_peers[rpc_id] = peer
	peer_joined.emit(rpc_id, peer)

func _on_peer_disconnected(rpc_id: int):
	var peer: MatchaPeer = _connected_peers[rpc_id]
	_connected_peers.erase(rpc_id)
	peer_left.emit(rpc_id, peer)
