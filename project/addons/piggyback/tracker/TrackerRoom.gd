class_name TrackerRoom extends PiggybackRoom

func _create_connection(url: String) -> PiggybackConnection:
	var connection:= TrackerConnection.new(url, _peer_id)
	connection.got_offer.connect(self._on_got_offer.bind(connection))
	connection.got_answer.connect(self._on_got_answer.bind(connection))
	connection.failure.connect(self._on_failure.bind(connection))
	return connection

func _on_poll():
	_create_offers()
	_handle_offers_announcment()

func _on_got_offer(offer: PiggybackConnection.Response, connection: PiggybackConnection):
	if offer.info_hash != _config.room_id: return
	if is_client and offer.peer_id != _config.room_id: return # Ignore offers from others than host (in client mode)

	if find_peer({ "id": offer.peer_id }) != null: return # Ignore if the peer is already known

	var answer_peer := PiggybackPeer.create_answer_peer(offer.offer_id, offer.sdp)
	var answer_rpc_id := 1 if is_client else generate_unique_id()
	answer_peer.id = offer.peer_id

	answer_peer.sdp_created.connect(self._send_answer_sdp.bind(answer_peer, connection))
	add_peer(answer_peer, answer_rpc_id)

	if answer_peer.start() != OK:
		remove_peer(answer_rpc_id)

func _on_got_answer(answer: PiggybackConnection.Response, connection: PiggybackConnection):
	if answer.info_hash != _config.room_id: return
	if is_client and answer.peer_id != _config.room_id: return # As client we just accept answers from the host

	var offer_peer: PiggybackPeer
	if is_client:
		if has_peer(1):
			offer_peer = get_peer(1).connection
			offer_peer.offer_id = answer.offer_id # Fix the offer_id since we gave the server alot of offers to choose from
	else:
		offer_peer = find_peer({ "offer_id": answer.offer_id })
	if offer_peer == null: return # Ignore if we dont know that offer

	offer_peer.id = answer.peer_id
	offer_peer.set_answer(answer.sdp)

# Methods specific to this protocol

func _handle_offers_announcment():
	var announce_offers = _gather_pooled_offers()
	if not announce_offers.is_empty():
		# Announce the pool
		for connection in _connections: # Announce the offers via every tracker
			connection.announce(_config.room_id, announce_offers)

func _gather_pooled_offers() -> Array:
	var unannounced_offers := find_peers({ "type": "offer", "announced": false })
	if unannounced_offers.size() == 0: return [] # There are no offers to announce

	var announce_offers: Array = [] # The array we need for the tracker offer announcements
	for offer_peer: PiggybackPeer in unannounced_offers:
		if not offer_peer.gathered: return [] # If we have ungathered offers we are not ready yet to announce.

		if is_client:
			# As client lets announce the host peer multiple times. Since we cannot have multiple peers with id 1 setup
			if unannounced_offers.size() != 1:
				push_error("In client mode you should have just 1 offer")
				return []
			for i in range(_config.offer_pool_size):
				announce_offers.append({ "offer_id": Utils.gen_id(), "offer": { "type": "offer", "sdp": offer_peer.local_sdp } })
		else:
			announce_offers.append({ "offer_id": offer_peer.offer_id, "offer": { "type": "offer", "sdp": offer_peer.local_sdp } })

	for offer_peer: PiggybackPeer in unannounced_offers:
		offer_peer.mark_as_announced()

	return announce_offers

func _create_offers() -> void:
	var unanswered_offers := find_peers({ "type": "offer", "answered": false })
	if unanswered_offers.size() > 0: return # There are ongoing offers. Dont refresh the pool.
	if is_client and has_peer(1): return # If we are already connected in client mode dont create further offers

	# Create as many offers as the pool_size
	for i in range(_config.offer_pool_size):
		_create_offer()
