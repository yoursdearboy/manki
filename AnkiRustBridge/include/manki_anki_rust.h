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

/**
 * Lists decks and scheduler counts from an existing local collection without
 * performing a network sync. The response has the same JSON shape as
 * manki_anki_fetch_decks().
 */
int manki_anki_load_decks(
    const char *collection_path,
    uint8_t **out_data,
    size_t *out_len
);

/**
 * Returns the next due card in a deck as UTF-8 JSON, including rendered
 * question and answer HTML. The result is `null` when the deck has no card
 * due now. Free the response with manki_anki_free_response().
 */
int manki_anki_get_next_card(
    const char *collection_path,
    int64_t deck_id,
    uint8_t **out_data,
    size_t *out_len
);

/**
 * Applies an Anki scheduler rating (0 Again, 1 Hard, 2 Good, 3 Easy) to the
 * current queued card. Free the response with manki_anki_free_response().
 */
int manki_anki_answer_card(
    const char *collection_path,
    int64_t deck_id,
    int64_t card_id,
    int32_t rating,
    uint32_t milliseconds_taken,
    uint8_t **out_data,
    size_t *out_len
);

#endif
