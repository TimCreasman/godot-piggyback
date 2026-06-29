extends Node2D

var server_room: PiggybackRoom
var client_room: PiggybackRoom

func _on_start_server_pressed():
	$start_server.disabled = true
	server_room = PiggybackRoom.create_server_room()
	$server_roomid_edit.text = server_room.id
	$client_roomid_edit.text = server_room.id
	$start_client.disabled = false
	$logs.text += "[Server] Joined (room_id=%s)\n" % [server_room.id]

	server_room.peer_joined.connect(func(_id: int, peer: PiggybackPeer):
		$logs.text += "[Server] Peer joined (id=%s)\n" % [peer.id]
	)
	server_room.peer_left.connect(func(_id: int, peer: PiggybackPeer):
		$logs.text += "[Server] Peer left (id=%s)\n" % [peer.id]
	)

func _on_start_client_pressed():
	$start_client.disabled = true
	$client_roomid_edit.editable = false
	client_room = PiggybackRoom.create_client_room($client_roomid_edit.text)
	$logs.text += "[Client] Joined (room_id=%s)\n" % [$client_roomid_edit.text]

	client_room.peer_joined.connect(func(_id: int, peer: PiggybackPeer):
		$logs.text += "[Client] Peer joined (id=%s)\n" % [peer.id]
	)
	client_room.peer_left.connect(func(_id: int, peer: PiggybackPeer):
		$logs.text += "[Client] Peer left (id=%s)\n" % [peer.id]
	)

func _on_client_roomid_edit_text_changed(new_text):
	$start_client.disabled = new_text.length() == 0
