#ifndef MANKI_ANKI_RUST_H
#define MANKI_ANKI_RUST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Stable, application-independent ABI for the Anki engine.
 *
 * This API intentionally deals only in opaque backend handles and serialized
 * protobuf messages. New Anki features can therefore be composed in Swift by
 * calling their service/method pair without adding another exported symbol or
 * rebuilding this framework.
 */
#define MANKI_ANKI_ABI_VERSION 1u

typedef struct MankiAnkiBackend MankiAnkiBackend;

typedef struct {
    const uint8_t *data;
    size_t len;
} MankiAnkiBytes;

typedef struct {
    uint8_t *data;
    size_t len;
} MankiAnkiOwnedBytes;

typedef enum {
    MANKI_ANKI_STATUS_OK = 0,
    MANKI_ANKI_STATUS_BACKEND_ERROR = 1,
    MANKI_ANKI_STATUS_INVALID_ARGUMENT = -1,
    MANKI_ANKI_STATUS_INITIALIZATION_ERROR = -2
} MankiAnkiStatus;

/** Returns the ABI version implemented by the loaded framework. */
uint32_t manki_anki_abi_version(void);

/**
 * Creates an opaque backend. `init` is a serialized BackendInit protobuf; an
 * empty slice selects rslib's defaults. The returned backend is independent
 * of any particular collection or application feature.
 */
MankiAnkiStatus manki_anki_backend_open(
    MankiAnkiBytes init,
    MankiAnkiBackend **out_backend
);

/**
 * Dispatches any rslib protobuf RPC. The service and method numbers come from
 * Anki's generated backend interface. Both successful replies and serialized
 * BackendError replies are returned in `out_response` and must be released
 * with manki_anki_bytes_free().
 */
MankiAnkiStatus manki_anki_backend_run(
    MankiAnkiBackend *backend,
    uint32_t service,
    uint32_t method,
    MankiAnkiBytes request,
    MankiAnkiOwnedBytes *out_response
);

/** Frees bytes returned by manki_anki_backend_run(). */
void manki_anki_bytes_free(MankiAnkiOwnedBytes bytes);

/** Releases an opaque backend. Passing NULL is allowed. */
void manki_anki_backend_close(MankiAnkiBackend *backend);

/*
 * Compatibility API retained for existing Manki clients. New integrations
 * should use the typed API above. These functions preserve source and binary
 * compatibility with framework artifacts produced before ABI version 1.
 */

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

/** Sets the card's standard Anki flag (0 for none, 1 through 7 for colors). */
int manki_anki_set_card_flag(
    const char *collection_path,
    int64_t card_id,
    uint8_t flag,
    uint8_t **out_data,
    size_t *out_len
);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif
