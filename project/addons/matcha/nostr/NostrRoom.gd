class_name NostrRoom extends PiggybackRoom

func _create_client(url: String) -> PiggybackClient:
	var client:= NostrClient.new(url, _peer_id)
	client.got_announcement.connect(self._on_got_announcement.bind(client))
	client.got_offer.connect(self._on_got_offer.bind(client))
	client.got_answer.connect(self._on_got_answer.bind(client))
	client.failure.connect(self._on_failure.bind(client))

	# Without pooling, we can announce immediately
	client.announce(_config.room_id)
	return client

func _on_poll():
	pass # This signalling requires nothing on polling

func _handle_offer(offer: PiggybackClient.Response, tracker_client: PiggybackClient):
	if find_peer({ "id": offer.peer_id }) == null: return # Ignore if the peer is not known
	var offer_peer = find_peer({ "id": offer.peer_id })

	# Ignore offers from peers with lower alphabetical peer_ids, this prevents offer glare
	if peer_id >= offer_peer.id: return

	# TODO Use the matcha approach
	offer_peer.set_remote_description("offer", offer.sdp)
	offer_peer.session_description_created.connect(self._send_answer_sdp.bind(offer_peer, tracker_client))

func _handle_answer(answer: PiggybackClient.Response, client: PiggybackClient):
	var offer_peer: MatchaPeer
	if is_client:
		if has_peer(1):
			offer_peer = get_peer(1).connection
			offer_peer.offer_id = answer.offer_id # Fix the offer_id since we gave the server alot of offers to choose from
	else:
		offer_peer = find_peer({ "id": answer.peer_id })
	if offer_peer == null: return # Ignore if we dont know that offer

	offer_peer.set_remote_description("answer", answer.sdp)

# Methods specific to this protocol

func _create_offer_from_announcement(announce: PiggybackClient.Response, client: PiggybackClient) -> void:
	var offer_peer = _create_offer()
	if not offer_peer: return

	offer_peer.id = announce.peer_id
	offer_peer.session_description_created.connect(client.offer.bind(_config.room_id, announce.peer_id))

func _on_got_announcement(announce: PiggybackClient.Response, relay_client: PiggybackClient) -> void:
	if announce.info_hash != _config.room_id: return
	if find_peer({ "id": announce.peer_id }) != null: return # Ignore if the peer is already known
	if is_client and announce.peer_id != _config.room_id: return # Ignore offers from others than host (in client mode)

	_create_offer_from_announcement(announce, relay_client)
