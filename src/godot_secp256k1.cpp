// nly slightly modified from the example in the secp256k1 lib:
// https://github.com/bitcoin-core/secp256k1/blob/master/examples/schnorr.c
#include "godot_secp256k1.h"

void Secp256k1::_bind_methods() {
	ClassDB::bind_method(D_METHOD("schnorr_sign"), &Secp256k1::schnorr_sign);
	ClassDB::bind_method(D_METHOD("keygen"), &Secp256k1::keygen);
	ClassDB::bind_method(D_METHOD("get_public_key"), &Secp256k1::get_public_key);
}

int Secp256k1::keygen() {
	/* Stock the seckey with randomness to prevent side-channel leakage.
	 * */
	if (!fill_random(seckey, sizeof(seckey))) {
		print_error("Failed to generate randomness\n");
		return godot::ERR_CANT_CREATE;
	}

	/* Try to create a keypair with a valid context. This only fails if the
	 * secret key is zero or out of range (greater than secp256k1's order). Note
	 * that the probability of this occurring is negligible with a properly
	 * functioning random number generator. */
	if (!secp256k1_keypair_create(ctx, &keypair, seckey)) {
		print_error("Generated secret key is invalid. This indicates an issue with the random number generator.\n");
		return godot::ERR_CANT_CREATE;
	}

	/* Extract the X-only public key from the keypair. We pass NULL for
	 * `pk_parity` as the parity isn't needed for signing or verification.
	 * `secp256k1_keypair_xonly_pub` supports returning the parity for
	 * other use cases such as tests or verifying Taproot tweaks.
	 * This should never fail with a valid context and public key. */
	int err = secp256k1_keypair_xonly_pub(ctx, &pubkey, NULL, &keypair);
	if (err != 1) {
		return godot::ERR_BUG;
	}

	err = secp256k1_xonly_pubkey_serialize(ctx, serialized_pubkey, &pubkey);
	if (err != 1) {
		return godot::ERR_BUG;
	}

	return godot::OK;
}

PackedByteArray Secp256k1::schnorr_sign(const String &msg_string) const {
	// Keep this variable alive to avoid immediately freeing the memory.
	CharString utf8_string = msg_string.utf8();
	const unsigned char *msg = (const unsigned char *)utf8_string.get_data();
	unsigned char msg_hash[32];

	// TODO add optional custom tag to Secp256k1 constructor
	unsigned char tag[] = { 'n', 'o', 's', 't', 'r', 'w', 'e', 'b', 'r', 't', 'c' };

	unsigned char randomize[32];
	unsigned char auxiliary_rand[32];
	unsigned char serialized_pubkey[32];
	unsigned char signature[64];

	int is_signature_valid, is_signature_valid2;
	int return_val;

	if (!fill_random(randomize, sizeof(randomize))) {
		printf("Failed to generate randomness\n");
		return PackedByteArray();
	}

	if (!ctx) {
		print_error("Failed to create secp256k1 context!");
		return PackedByteArray();
	}

	/* Randomizing the context is recommended to protect against side-channel
	 * leakage See `secp256k1_context_randomize` in secp256k1.h for more
	 * information about it. This should never fail. */
	int err = secp256k1_context_randomize(ctx, randomize);
	assert(err);

	/*** Signing ***/

	/* Instead of signing (possibly very long) messages directly, we sign a
	 * 32-byte hash of the message in this example.
	 *
	 * We use secp256k1_tagged_sha256 to create this hash. This function expects
	 * a context-specific "tag", which restricts the context in which the signed
	 * messages should be considered valid. For example, if protocol A mandates
	 * to use the tag "my_fancy_protocol" and protocol B mandates to use the tag
	 * "my_boring_protocol", then signed messages from protocol A will never be
	 * valid in protocol B (and vice versa), even if keys are reused across
	 * protocols. This implements "domain separation", which is considered good
	 * practice. It avoids attacks in which users are tricked into signing a
	 * message that has intended consequences in the intended context (e.g.,
	 * protocol A) but would have unintended consequences if it were valid in
	 * some other context (e.g., protocol B). */
	return_val = secp256k1_tagged_sha256(ctx, msg_hash, tag, sizeof(tag), msg, sizeof(msg));
	assert(return_val);

	/* Generate 32 bytes of randomness to use with BIP-340 schnorr signing. */
	if (!fill_random(auxiliary_rand, sizeof(auxiliary_rand))) {
		print_error("Failed to generate randomness\n");
		return PackedByteArray();
	}

	/* Generate a Schnorr signature.
	 *
	 * We use the secp256k1_schnorrsig_sign32 function that provides a simple
	 * interface for signing 32-byte messages (which in our case is a hash of
	 * the actual message). BIP-340 recommends passing 32 bytes of randomness
	 * to the signing function to improve security against side-channel attacks.
	 * Signing with a valid context, a 32-byte message, a verified keypair, and
	 * any 32 bytes of auxiliary random data should never fail. */
	return_val = secp256k1_schnorrsig_sign32(ctx, signature, msg_hash, &keypair, auxiliary_rand);
	assert(return_val);

	/*** Verification ***/

	/* Deserialize the public key. This will return 0 if the public key can't
	 * be parsed correctly */
	// if (!secp256k1_xonly_pubkey_parse(ctx, &pubkey, serialized_pubkey)) {
	// 	print_error("Failed parsing the public key\n");
	// 	return PackedByteArray();
	// }

	/* Compute the tagged hash on the received messages using the same tag as the signer. */
	return_val = secp256k1_tagged_sha256(ctx, msg_hash, tag, sizeof(tag), msg, sizeof(msg));
	assert(return_val);

	/* Verify a signature. This will return 1 if it's valid and 0 if it's not. */
	is_signature_valid = secp256k1_schnorrsig_verify(ctx, signature, msg_hash, 32, &pubkey);
	if (!is_signature_valid) {
		print_error("Signature invalid. Make sure to run keygen() first\n");
		return PackedByteArray();
	}
	assert(is_signature_valid);

	// print_line(vformat("Is the signature valid? %s\n", is_signature_valid ? "true" : "false"));
	// print_line("Secret Key: ");
	//
	// print_hex(seckey, sizeof(seckey));
	// printf("Public Key: ");
	// print_hex(serialized_pubkey, sizeof(serialized_pubkey));
	// printf("Signature: ");
	// print_hex(signature, sizeof(signature));

	return _unsigned_char_to_packed_byte_array(signature, 64);
}

PackedByteArray Secp256k1::get_public_key() {
	/* Deserialize the public key. This will return 0 if the public key can't
	 * be parsed correctly */
	// if (!secp256k1_xonly_pubkey_parse(ctx, &pubkey, serialized_pubkey)) {
	// 	print_error("Failed parsing the public key\n");
	// 	return PackedByteArray();
	// }

	return _unsigned_char_to_packed_byte_array(serialized_pubkey, 32);
}

PackedByteArray Secp256k1::_unsigned_char_to_packed_byte_array(const unsigned char *c_str, size_t size) {
	PackedByteArray p_array;
	p_array.resize(size);

	uint8_t *write_ptr = p_array.ptrw();
	std::memcpy(write_ptr, c_str, size);

	return p_array;
}
