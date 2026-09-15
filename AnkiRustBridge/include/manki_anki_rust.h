#ifndef MANKI_ANKI_RUST_H
#define MANKI_ANKI_RUST_H

#include <stddef.h>
#include <stdint.h>

/**
 * Creates an Anki rslib backend.
 *
 * init_data is a serialized BackendInit protobuf. Pass NULL and zero to use
 * rslib's default initialization. On success, out_backend receives an opaque
 * handle that must be released with manki_anki_close_backend().
 */
int manki_anki_open_backend(
    const uint8_t *init_data,
    size_t init_len,
    int64_t *out_backend
);

/**
 * Runs an rslib backend service method using protobuf bytes.
 *
 * A return value of 0 means out_data contains the method response. A return
 * value of 1 means out_data contains rslib's serialized BackendError. In both
 * cases, free out_data with manki_anki_free_response(). A negative value is a
 * bridge-level failure and produces no response buffer.
 */
int manki_anki_run_method(
    int64_t backend,
    uint32_t service,
    uint32_t method,
    const uint8_t *input_data,
    size_t input_len,
    uint8_t **out_data,
    size_t *out_len
);

/** Releases a buffer returned by manki_anki_run_method(). */
void manki_anki_free_response(uint8_t *data, size_t len);

/** Closes and releases a backend handle. Safe to call with zero. */
void manki_anki_close_backend(int64_t backend);

/**
 * Syncs an isolated local collection with AnkiWeb and lists its decks.
 *
 * The result is UTF-8 JSON (`[{"id": 1, "name": "Default"}]`) on a zero
 * return value. A return value of 1 has a UTF-8 error message instead. This
 * operation never uploads and rejects any full-sync conflict. Free either
 * response with manki_anki_free_response().
 */
int manki_anki_fetch_decks(
    const char *collection_path,
    const char *endpoint,
    const char *username,
    const char *password,
    uint8_t **out_data,
    size_t *out_len
);

#endif
