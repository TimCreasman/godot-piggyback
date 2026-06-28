class_name NostrRoom extends PiggybackRoom

var _secp256k1

func _init(config:={}):
	_secp256k1 = Secp256k1.new()
	var err: int = _secp256k1.keygen()

	super._init(config)

func _create_connection(url: String) -> PiggybackConnection:
	var connection:= NostrConnection.new(url, _peer_id, _secp256k1)
	connection.got_announcement.connect(self._on_got_announcement.bind(connection))
	connection.got_offer.connect(self._on_got_offer.bind(connection))
	connection.got_answer.connect(self._on_got_answer.bind(connection))
	connection.failure.connect(self._on_failure.bind(connection))

	# Without pooling, we can announce immediately
	connection.announce(_config.room_id)
	return connection

func _on_poll():
	pass # This strategy does not need to react to polling

func _on_got_offer(offer: PiggybackConnection.Response, tracker_client: PiggybackConnection):
	if offer.info_hash != _config.room_id: return

	var offer_peer = find_peer({ "id": offer.peer_id })
	if offer_peer == null: # Create peer if not known at this time
		offer_peer = _create_offer()
		offer_peer.id = offer.peer_id

	# Ignore offers from peers with lower alphabetical peer_ids, this prevents offer glare in a mesh network
	if is_mesh and peer_id >= offer_peer.id: return

	if is_client and offer.peer_id != _config.room_id: return # Ignore offers from others than host (in client mode)

	# TODO Use the matcha approach
	offer_peer.set_remote_description("offer", offer.sdp)
	offer_peer.session_description_created.connect(self._send_answer_sdp.bind(offer_peer, tracker_client))

func _on_got_answer(answer: PiggybackConnection.Response, client: PiggybackConnection):
	if answer.info_hash != _config.room_id: return
	if is_client and answer.peer_id != _config.room_id: return # As client we just accept answers from the host

	var offer_peer: PiggybackPeer
	if is_client:
		if has_peer(1):
			offer_peer = get_peer(1).connection
			offer_peer.id = answer.peer_id # Fix the offer_id since we gave the server alot of offers to choose from
	else:
		offer_peer = find_peer({ "id": answer.peer_id })
	if offer_peer == null: return # Ignore if we dont know that offer

	offer_peer.set_remote_description("answer", answer.sdp)

# Methods specific to this protocol

func _create_offer_from_announcement(announce: PiggybackConnection.Response, client: PiggybackConnection) -> void:
	var offer_peer = _create_offer()
	if not offer_peer: return

	offer_peer.id = announce.peer_id
	offer_peer.session_description_created.connect(client.offer.bind(_config.room_id, announce.peer_id))

func _on_got_announcement(announce: PiggybackConnection.Response, relay_client: PiggybackConnection) -> void:
	if announce.info_hash != _config.room_id: return
	if find_peer({ "id": announce.peer_id }) != null: return # Ignore if the peer is already known
	if is_client and announce.peer_id != _config.room_id: return # Ignore offers from others than host (in client mode)

	_create_offer_from_announcement(announce, relay_client)
