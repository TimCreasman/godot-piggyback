# The TrackerClient is a simple implementation of a WebTorrent Tracker Client
# Learn more about it here (js): https://github.com/webtorrent/bittorrent-tracker
extends PiggybackConnection

const DEFAULT_TRACKER_URLS: Array[String] = [
	"wss://tracker.webtorrent.dev",
	"wss://tracker.openwebtorrent.com",
	"wss://tracker.btorrent.xyz",
	"wss://tracker.files.fm:7073/announce"
]

func _init(url: String, peer_id:=Utils.gen_id()) -> void:
	super._init(url, PiggybackRoom.Protocol.TRACKER, peer_id)

# This method is used to share our answer to an offer
func _on_answer(info_hash: String, to_peer_id: String, offer_id: String, sdp: String) -> void:
	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _self_id,
		"to_peer_id": to_peer_id,
		"offer_id": offer_id,
		"answer": {
			"type": "answer",
			"sdp": sdp
		}
	})

# This method is used to
func _on_announce(info_hash: String, offers: Array) -> void:
	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _self_id,
		"numwant": offers.size(),
		"offers": offers
	})

func _on_offer(sdp: String, info_hash: String, to_peer_id: String) -> void:
	pass # Not implemented for this strategy

func _on_message(data) -> void:
	if not typeof(data) == TYPE_DICTIONARY: return
	if "failure reason" in data:
		failure.emit(data["failure reason"])
		return
	if not "action" in data or data.action != "announce": return
	if not "info_hash" in data: return

	if "peer_id" in data and "offer_id" in data:
		var response := Response.new()

		response.info_hash = data.info_hash
		response.peer_id = data.peer_id
		response.offer_id = data.offer_id

		if "offer" in data:
			response.type = "offer"
			response.sdp = data.offer.sdp
			got_offer.emit(response)
		if "answer" in data:
			response.type = "answer"
			response.sdp = data.answer.sdp
			got_answer.emit(response)
