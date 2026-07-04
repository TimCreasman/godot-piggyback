extends PiggybackConnection
# The NostrClient is a simple implementation of the Trysteroa nostr package
# Learn more about it here: https://github.com/dmotz/trystero/blob/main/packages/nostr/src/index.ts#L43

## Only uses seven of the available relays for now. Batching should be introduced before this entire array gets used
const DEFAULT_RELAY_URLS: Array[String] = [
	"wss://basspistol.org",
	"wss://bucket.coracle.social",
	"wss://chorus.almostmachines.dev",
	"wss://chorus.pjv.me",
	"wss://communities.nos.social",
	"wss://ftp.halifax.rwth-aachen.de/nostr",
	"wss://hol.is",
	# "wss://hornetstorage.net/relay",
	# "wss://koru.bitcointxoko.org",
	# "wss://nos.lol",
	# "wss://nostr-01.uid.ovh",
	# "wss://nostr-01.yakihonne.com",
	# "wss://nostr-relay.corb.net",
	# "wss://nostr.data.haus",
	# "wss://nostr.islandarea.net",
	# "wss://nostr.sathoarder.com",
	# "wss://nostr.self-determined.de",
	# "wss://nostr.tegila.com.br",
	# "wss://nostr.vulpem.com",
	# "wss://purplerelay.com",
	# "wss://relay-can.zombi.cloudrodion.com",
	# "wss://relay-rpi.edufeed.org",
	# "wss://relay.agorist.space",
	# "wss://relay.angor.io",
	# "wss://relay.artio.inf.unibe.ch",
	# "wss://relay.binaryrobot.com",
	# "wss://relay.damus.io",
	# "wss://relay.froth.zone",
	# "wss://relay.libernet.app",
	# "wss://relay.mostr.pub",
	# "wss://relay.mostro.network",
	# "wss://relay.nostr.place",
	# "wss://relay.nostrdice.com",
	# "wss://relay.notoshi.win",
	# "wss://relay.sigit.io",
	# "wss://relay02.lnfi.network",
	# "wss://relay2.angor.io",
	# "wss://schnorr.me",
	# "wss://slick.mjex.me",
	# "wss://social.amanah.eblessing.co",
	# "wss://staging.yabu.me",
	# "wss://strfry.openhoofd.nl",
	# "wss://strfry.shock.network",
	# "wss://testnet-relay.samt.st",
	# "wss://top.testrelay.top",
	# "wss://x.kojira.io",
	# "wss://yabu.me/v2",
]

class NostrProtocol:
	var kind: int #
	var pubkey: String # Schnorr pub key
	var created_at: int # Date sent
	var tags: Array[Array] # Array of tuples of tag types
	var content: String # Content to send to peer
	var id: String # Sha256 hash of payload
	var sig: String # Schnorr signature

	func to_dict() -> Dictionary:
		return {
			kind = kind,
			pubkey = pubkey,
			created_at = created_at,
			tags = tags,
			content = content,
			id = id,
			sig = sig,
		}

const _event_msg_type = "EVENT"

var _pubkey
var _secp256k1

func _init(url: String, peer_id:=Utils.gen_id(), secp256k1: Secp256k1 = Secp256k1.new()) -> void:
	super._init(url, PiggybackRoom.Protocol.NOSTR, peer_id)
	_secp256k1 = secp256k1
	_pubkey = secp256k1.get_public_key().hex_encode()

func _on_answer(info_hash: String, to_peer_id: String, _offer_id: String, sdp: String) -> void:
	var content = JSON.stringify({
		"info_hash": info_hash,
		"peer_id": _self_id,
		"answer": sdp
	})

	_socket.send(_create_event(info_hash + to_peer_id, content))

func _on_offer(sdp: String, info_hash: String, to_peer_id: String) -> void:

	var content = JSON.stringify({
		"info_hash": info_hash,
		"peer_id": _self_id,
		"offer": sdp
	})

	_socket.send(_create_event(info_hash + to_peer_id, content))

func _on_announce(info_hash: String, _offers: Array) -> void:

	var content = JSON.stringify({
		"info_hash": info_hash,
		"peer_id": _self_id,
	})

	_socket.send(_create_event(info_hash, content))

	# Subscribe to the info_hash to receive all other announcements
	_socket.send(_subscribe(info_hash))
	# Also want to subscribe/create our own self topic, this is how this peer will get notified of answers
	_socket.send(_subscribe(info_hash + _self_id))

func _on_message(data) -> void:
	if not typeof(data) == TYPE_ARRAY: return

	var payload: Array = []
	payload.assign(data)
	if payload.size() == 0: return

	var msg_type = payload[0] as String

	if msg_type != _event_msg_type:
		if msg_type == "NOTICE":
			push_error("Error from %s: %s" % [_url, payload[1]])
		if msg_type == "OK" && not payload.get(2):
			push_error("Error from %s: %s" % [_url, payload[1]])
		return

	if payload.get(2) and typeof(payload.get(2)) == TYPE_DICTIONARY and "content" in payload.get(2):
		var content = JSON.parse_string(payload.get(2)["content"])

		var response := Response.new()
		response.info_hash = content.info_hash
		response.peer_id = content.peer_id

		# Ignore events sent by me
		if content.peer_id == _self_id:
			return

		if "offer" in content:
			response.sdp = content.offer
			got_offer.emit(response)
		elif "answer" in content:
			response.sdp = content.answer
			got_answer.emit(response)
		else:
			got_announcement.emit(response)

func _create_event(info_hash: String, content: String) -> Array:
	var payload = NostrProtocol.new()
	payload.kind = _info_hash_to_kind(info_hash)
	payload.tags = [["x", info_hash]] as Array[Array]
	payload.created_at = _now()
	payload.content = content
	payload.pubkey = _pubkey

	var id = JSON.stringify([
		0,
		payload.pubkey,
		payload.created_at,
		payload.kind,
		payload.tags,
		payload.content
	]).sha256_buffer()

	payload.id = id.hex_encode()
	payload.sig = _secp256k1.schnorr_sign(id).hex_encode()

	return [
		_event_msg_type,
		payload.to_dict()
	]

func _subscribe(topic: String) -> Array:
	return [
		"REQ",
		topic,
		{
			"kinds": [_info_hash_to_kind(topic)],
			"since": _now(),
			"#x": [topic]
		}
	]

func _now() -> int:
	return floor(Time.get_unix_time_from_system())

# Convert the info hash to a kind within the range of 20,000-29,999
# This is within the range of ephemeral events
func _info_hash_to_kind(info_hash: String) -> int:
	var sum = 0
	for byte in info_hash.to_ascii_buffer():
		sum += byte
	return (sum % 10_000) + 20_000
