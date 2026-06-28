## This is the central interface for sending data across either a webtorrent tracker or nostr relay. It is protocol-agnostic
@abstract
class_name PiggybackConnection extends RefCounted
const Utils := preload("../lib/Utils.gd")
const WebSocketClient := preload("../lib/WebSocketClient.gd")

# Classes
class Response:
	var type: String # The type of the response ("offer" or "answer")
	var info_hash: String # The info_hash which the repsonse belongs to
	var peer_id: String # The self_id of the other peer (who've sent it)
	var offer_id: String # The offer_id that this offer/answer belongs to
	var sdp: String # The sdp (webrtc session description) of the other peer

# Signals
signal connected # Emitted when we connected to the tracker
signal disconnected # Emitted when we disconnected from the tracker
signal reconnecting # Emitted when we are reconnecting to the tracker (after unexpected disconnect)
signal failure(reason: String) # Emitted when the tracker did not like something
signal got_offer(offer: Response) # Emitted when we got an offer
signal got_answer(answer: Response) # Emitted when we got an answer
signal got_announcement(announce: Response) # Emitted when we got an answer

# Members
var _socket: WebSocketClient # An internal reference to the websocket client
var _self_id: String # Our self_id that is used to identify us
var _url: String # The tracker we are connected to
var _protocol: PiggybackRoom.Protocol

# Getters
var is_connected:
	get: return _socket != null and _socket.is_connected
var tracker_url:
	get: return _url
var self_id:
	get: return _self_id

# Constructor
func _init(url: String, protocol := PiggybackRoom.Protocol.NOSTR, peer_id:=Utils.gen_id()) -> void:
	_url = url
	_protocol = protocol
	_self_id = peer_id

	_socket = WebSocketClient.new(_url, {
		"mode": WebSocketClient.Mode.JSON,
		"reconnect_time": 3,
		"reconnect_tries": 3
	})
	_socket.connected.connect(self._on_tracker_connected)
	_socket.disconnected.connect(self._on_tracker_disconnected)
	_socket.reconnecting.connect(self._on_tracker_reconnecting)
	_socket.message.connect(self._on_message)

func answer(info_hash: String, to_peer_id: String, offer_id: String, sdp: String) -> void:
	_call_when_connected(_on_answer, info_hash, to_peer_id, offer_id, sdp)

func announce(info_hash: String, offers: Array = []) -> void:
	_call_when_connected(_on_announce, info_hash, offers)

func offer(_type: String, sdp: String, info_hash: String, to_peer_id: String) -> void:
	_call_when_connected(_on_offer, sdp, info_hash, to_peer_id)

@abstract
func _on_message(data) -> void

@abstract
func _on_answer(info_hash: String, to_peer_id: String, offer_id: String, sdp: String) -> void

@abstract
func _on_announce(info_hash: String, offers: Array) -> void

@abstract
func _on_offer(sdp: String, info_hash: String, to_peer_id: String) -> void

func _call_when_connected(function: Callable, ...args: Array) -> void:
	if not is_connected:
		connected.connect(function.bindv(args), CONNECT_ONE_SHOT)
		return
	function.callv(args)

func _on_tracker_connected() -> void:
	connected.emit()

func _on_tracker_disconnected() -> void:
	disconnected.emit()

func _on_tracker_reconnecting() -> void:
	reconnecting.emit()
