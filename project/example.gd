extends Node


func _ready() -> void:
	var secp256k1 := Secp256k1.new()
	var err: int = secp256k1.keygen();
	var public_key = secp256k1.get_public_key();
	print("Test Message".sha256_text())


	var signed_message = secp256k1.schnorr_sign("Test Message".sha256_text())

	print(signed_message.hex_encode())
