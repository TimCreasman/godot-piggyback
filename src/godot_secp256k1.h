#pragma once

#include "../secp256k1/include/secp256k1_extrakeys.h"
#include "../secp256k1/include/secp256k1_schnorrsig.h"
#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/string.hpp"
#include "utils.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cstddef>
#include <cstdlib>

using namespace godot;

class Secp256k1 : public RefCounted {
	GDCLASS(Secp256k1, RefCounted)

protected:
	static void _bind_methods();

public:
	Secp256k1() {
		ctx = secp256k1_context_create(SECP256K1_CONTEXT_NONE);
	};

	~Secp256k1() {
		secp256k1_context_destroy(ctx);
		secure_erase(seckey, sizeof(seckey));
	}

	/**
	 * Creates the secret and public keys used for signing
	 **/
	int keygen();

	/** 32 byte public key.
	 * */
	PackedByteArray get_public_key();

	/** 64 byte schnorr sign.
	 * */
	PackedByteArray schnorr_sign(const PackedByteArray &msg_string) const;
	// void pubkey() const;

private:
	unsigned char seckey[32];
	unsigned char serialized_pubkey[32];
	secp256k1_xonly_pubkey pubkey;
	secp256k1_keypair keypair;
	secp256k1_context *ctx = nullptr;

	static PackedByteArray _unsigned_char_to_packed_byte_array(const unsigned char *c_str, size_t size);
};
