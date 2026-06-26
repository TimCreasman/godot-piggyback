# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

class_name MatchaRoomTest extends WebRTCMultiplayerPeer
const Utils := preload("./lib/Utils.gd")
const TrackerClient := preload("./tracker/TrackerClient.gd")
const NostrClient := preload("./nostr/NostrClient.gd")
const MatchaPeer := preload("./MatchaPeer.gd")

# Constants
enum State { NEW, STARTED }

# Signals
signal peer_joined(rpc_id: int, peer: MatchaPeer) # Emitted when a peer joined the room
signal peer_left(rpc_id: int, peer: MatchaPeer) # Emitted when a peer left the room

# Members
var _state := State.NEW # Internal state
var _socket_urls := [] # A list of tracker urls
var _tracker_clients: Array[PiggybackClient] = [] # A list of tracker clients we use to share/get offers/answers
var _id: String # An unique id for this room
var _peer_id := Utils.gen_id()
var _type: String
var _offer_timeout := 120
var _pool_size := 10
var _connected_peers = {}

# Getters
var rpc_id:
	get: return get_unique_id()
var peer_id:
	get: return _peer_id
var type:
	get: return _type
var id:
	get: return _id
var connected_peers:
	get: return _connected_peers.values()
var peers:
	get: return get_peers().values().map(func(v): return v.connection)

# Static methods
static func create_mesh_room(options:={}) -> MatchaRoomTest:
	options.type = "mesh"
	return MatchaRoomTest.new(options)

static func create_server_room(options:={}) -> MatchaRoomTest:
	options.type = "server"
	return MatchaRoomTest.new(options)

static func create_client_room(room_id: String, options:={}) -> MatchaRoomTest:
	options.type = "client"
	options.room_id = room_id
	return MatchaRoomTest.new(options)

# Constructor
func _init(options:={}):
	if not "pool_size" in options: options.pool_size = _pool_size
	if not "offer_timeout" in options: options.offer_timeout = _offer_timeout
	if not "identifier" in options: options.identifier = "com.matcha.default"
	# key off something to decide whether to use nostr or tracker
	if not "tracker_urls" in options: options.tracker_urls = NostrClient.DEFAULT_RELAY_URLS

	if not "room_id" in options: options.room_id = options.identifier.sha1_text().substr(0, 20)
	if not "type" in options: options.type = "mesh"
	if not "autostart" in options: options.autostart = true
	_socket_urls = options.tracker_urls
	_pool_size = options.pool_size
	_offer_timeout = options.offer_timeout
	_id = options.room_id
	_type = options.type

	peer_connected.connect(self._on_peer_connected)
	peer_disconnected.connect(self._on_peer_disconnected)

	if options.autostart:
		start.call()

# Public methods
func start() -> Error:
	if _state != State.NEW:
		push_error("Already started")
		return Error.ERR_ALREADY_IN_USE

	_state = State.STARTED

	if _type == "mesh":
		var err := create_mesh(generate_unique_id())
		if err != OK:
			push_error("Creating mesh failed")
			return err
	elif _type == "client":
		var err := create_client(generate_unique_id())
		if err != OK:
			push_error("Creating client failed")
			return err
	elif _type == "server":
		_id = _peer_id # Our room_id should be our peer_id to identify ourself as the server
		var err := create_server()
		if err != OK:
			push_error("Creating server failed")
			return err
	else:
		push_error("Invalid type")
		return Error.ERR_INVALID_DATA

	# Create the tracker_clients based on the urls
	for url in _socket_urls:
		var relay_client = NostrClient.new(url, _peer_id)
		relay_client.got_announcement.connect(self._on_got_announcement.bind(relay_client))
		relay_client.got_offer.connect(self._on_got_offer.bind(relay_client))
		relay_client.got_answer.connect(self._on_got_answer.bind(relay_client))
		relay_client.failure.connect(self._on_failure.bind(relay_client))

		print("ANNOUNCING RELAY CLIENT %s with id %s" % [url, _peer_id])
		relay_client.announce(_id)
		_tracker_clients.append(relay_client)

	Engine.get_main_loop().process_frame.connect(self.__poll)
	return Error.OK

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

# Private methods
func __poll():
	poll()

func _remove_unanswered_offer(offer_id: String) -> void:
	var offer := find_peer({ "answered": false, "offer_id": offer_id })
	if offer != null:
		offer.close()

func _create_offer(announce: PiggybackClient.Response, relay_client: PiggybackClient) -> void:
	if _type == "client" and has_peer(1): return # We already created the host offer. So lets ignore the offer creating

	var offer_peer := MatchaPeer.create_offer_peer()
	var offer_rpc_id := 1 if _type == "client" else generate_unique_id()
	offer_peer.id = announce.peer_id

	add_peer(offer_peer, offer_rpc_id)

	offer_peer.session_description_created.connect(relay_client.offer.bind(_id, announce.peer_id))

	if offer_peer.start() == OK:
		# Cleanup when the offer was not answered for long time
		Engine.get_main_loop().create_timer(_offer_timeout).timeout.connect(self._remove_unanswered_offer.bind(offer_peer.offer_id))
	else:
		remove_peer(offer_rpc_id)

func _send_answer_sdp(_type: String, answer_sdp: String, peer: MatchaPeer, tracker_client: PiggybackClient):
	tracker_client.answer(_id, peer.id, peer.offer_id, answer_sdp)

func _on_got_announcement(announce: PiggybackClient.Response, relay_client: PiggybackClient) -> void:
	if announce.info_hash != _id: return
	if find_peer({ "id": announce.peer_id }) != null: return # Ignore if the peer is already known
	if _type == "client" and announce.peer_id != _id: return # Ignore offers from others than host (in client mode)

	_create_offer(announce, relay_client)

func _on_got_offer(offer: PiggybackClient.Response, tracker_client: PiggybackClient) -> void:
	if offer.info_hash != _id: return
	if find_peer({ "id": offer.peer_id }) == null: return # Ignore if the peer is not known
	if _type == "client" and offer.peer_id != _id: return # Ignore offers from others than host (in client mode)

	var offer_peer = find_peer({ "id": offer.peer_id })

	# Ignore offers from peers with lower alphabetical peer_ids, this prevents offer glare
	if peer_id >= offer_peer.id: return

	# TODO Use the matcha approach
	offer_peer.set_remote_description("offer", offer.sdp)
	offer_peer.session_description_created.connect(self._send_answer_sdp.bind(offer_peer, tracker_client))


func _on_got_answer(answer: PiggybackClient.Response, tracker_client: PiggybackClient) -> void:
	if answer.info_hash != _id: return
	if _type == "client" and answer.peer_id != _id: return # As client we just accept answers from the host

	var offer_peer: MatchaPeer
	if _type == "client":
		if has_peer(1):
			offer_peer = get_peer(1).connection
			offer_peer.offer_id = answer.offer_id # Fix the offer_id since we gave the server alot of offers to choose from
	else:
		offer_peer = find_peer({ "id": answer.peer_id })
	if offer_peer == null: return # Ignore if we dont know that offer

	offer_peer.set_remote_description("answer", answer.sdp)

	# TODO Use this match approach
	# offer_peer.set_answer(answer.sdp)

func _on_failure(reason: String, tracker_client: PiggybackClient) -> void:
	print("Tracker failure: ", reason, ", Tracker: ", tracker_client.tracker_url)

func _on_peer_connected(rpc_id: int):
	var peer: MatchaPeer = get_peer(rpc_id).connection
	_connected_peers[rpc_id] = peer
	peer_joined.emit(rpc_id, peer)

func _on_peer_disconnected(rpc_id: int):
	var peer: MatchaPeer = _connected_peers[rpc_id]
	_connected_peers.erase(rpc_id)
	peer_left.emit(rpc_id, peer)
