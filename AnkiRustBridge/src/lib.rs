//! A deliberately small C ABI around Anki's `rslib` backend.
//!
//! The API mirrors the bridge pattern used by Anki mobile clients: callers
//! serialize Anki protobuf requests, invoke a backend service/method pair, and
//! deserialize the returned protobuf. Keeping that contract intact prevents a
//! second, drift-prone Swift implementation of Anki's sync and collection
//! behavior.

use std::{
    ffi::CStr,
    fs,
    os::raw::{c_char, c_int},
    path::{Path, PathBuf},
    ptr, slice,
};

use anki::backend::{init_backend, Backend};
use anki_proto::{
    backend::BackendError,
    card_rendering::{
        av_tag::Value as AvTagValue, rendered_template_node::Value as RenderedNodeValue,
        ExtractAvTagsRequest, ExtractAvTagsResponse, RenderCardResponse, RenderExistingCardRequest,
    },
    cards::SetFlagRequest,
    collection::{CloseCollectionRequest, OpenCollectionRequest},
    decks::{DeckId, DeckNames, DeckTreeNode, DeckTreeRequest, GetDeckNamesRequest},
    scheduler::{card_answer::Rating, CardAnswer, GetQueuedCardsRequest, QueuedCards},
    sync::{
        sync_collection_response::ChangesRequired, FullUploadOrDownloadRequest,
        MediaSyncStatusResponse, SyncAuth, SyncCollectionRequest, SyncCollectionResponse,
        SyncLoginRequest,
    },
};
use prost::Message;
use serde_json::json;

const OK: c_int = 0;
const BACKEND_ERROR: c_int = 1;
const INVALID_ARGUMENT: c_int = -1;
const INITIALIZATION_ERROR: c_int = -2;
const FETCH_ERROR: c_int = 1;

const SERVICE_SYNC: u32 = 1;
const SERVICE_COLLECTION: u32 = 3;
const SERVICE_DECKS: u32 = 7;
const SERVICE_CARDS: u32 = 5;
const OPEN_COLLECTION: u32 = 0;
const CLOSE_COLLECTION: u32 = 1;
const SYNC_LOGIN: u32 = 3;
const MEDIA_SYNC_STATUS: u32 = 2;
const SYNC_COLLECTION: u32 = 5;
const FULL_UPLOAD_OR_DOWNLOAD: u32 = 6;
const DECK_TREE: u32 = 4;
const GET_DECK_NAMES: u32 = 13;
const SET_CURRENT_DECK: u32 = 22;
const SET_FLAG: u32 = 4;
const GET_QUEUED_CARDS: u32 = 3;
const ANSWER_CARD: u32 = 4;
const RENDER_EXISTING_CARD: u32 = 6;
// BackendCardRenderingService adds three backend-only methods before the
// CardRenderingService methods. ExtractAvTags is therefore method 3 when
// invoked through Backend::run_service_method (rather than method 0 from the
// protobuf service declaration).
const EXTRACT_AV_TAGS: u32 = 3;
const SERVICE_SCHEDULER: u32 = 13;
const SERVICE_CARD_RENDERING: u32 = 27;
#[cfg(test)]
const SERVICE_IMPORT_EXPORT: u32 = 39;
#[cfg(test)]
const IMPORT_ANKI_PACKAGE: u32 = 2;

/// Version of the stable C ABI declared in `manki_anki_rust.h`.
#[no_mangle]
pub extern "C" fn manki_anki_abi_version() -> u32 {
    1
}

/// Borrowed bytes passed across the C ABI.
#[repr(C)]
pub struct MankiAnkiBytes {
    data: *const u8,
    len: usize,
}

/// Owned bytes returned across the C ABI.
#[repr(C)]
pub struct MankiAnkiOwnedBytes {
    data: *mut u8,
    len: usize,
}

/// Creates a backend through the stable, typed ABI.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_backend_open(
    init: MankiAnkiBytes,
    out_backend: *mut *mut Backend,
) -> c_int {
    if out_backend.is_null() || (init.data.is_null() && init.len != 0) {
        return INVALID_ARGUMENT;
    }
    unsafe { *out_backend = ptr::null_mut() };

    let init_bytes = if init.len == 0 {
        anki_proto::backend::BackendInit::default().encode_to_vec()
    } else {
        unsafe { slice::from_raw_parts(init.data, init.len) }.to_vec()
    };
    match init_backend(&init_bytes) {
        Ok(backend) => {
            unsafe { *out_backend = Box::into_raw(Box::new(backend)) };
            OK
        }
        Err(_) => INITIALIZATION_ERROR,
    }
}

/// Dispatches any backend method without imposing feature-specific policy.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_backend_run(
    backend: *mut Backend,
    service: u32,
    method: u32,
    request: MankiAnkiBytes,
    out_response: *mut MankiAnkiOwnedBytes,
) -> c_int {
    if backend.is_null() || out_response.is_null() || (request.data.is_null() && request.len != 0) {
        return INVALID_ARGUMENT;
    }
    unsafe {
        (*out_response).data = ptr::null_mut();
        (*out_response).len = 0;
    }
    let input = if request.len == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(request.data, request.len) }
    };
    let result = unsafe { &*backend }.run_service_method(service, method, input);
    let (status, bytes) = match result {
        Ok(bytes) => (OK, bytes),
        Err(bytes) => (BACKEND_ERROR, bytes),
    };
    let mut output = MankiAnkiOwnedBytes {
        data: ptr::null_mut(),
        len: 0,
    };
    unsafe { set_output(bytes, &mut output.data, &mut output.len) };
    unsafe { *out_response = output };
    status
}

/// Releases a response returned by the stable ABI.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_bytes_free(bytes: MankiAnkiOwnedBytes) {
    unsafe { manki_anki_free_response(bytes.data, bytes.len) };
}

/// Releases a backend returned by the stable ABI.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_backend_close(backend: *mut Backend) {
    if !backend.is_null() {
        let _ = unsafe { Box::from_raw(backend) };
    }
}

/// Initializes an Anki backend from a serialized `BackendInit` protobuf.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_open_backend(
    init_data: *const u8,
    init_len: usize,
    out_backend: *mut i64,
) -> c_int {
    if out_backend.is_null() {
        return INVALID_ARGUMENT;
    }
    unsafe { *out_backend = 0 };
    let mut backend = ptr::null_mut();
    let status = unsafe {
        manki_anki_backend_open(
            MankiAnkiBytes {
                data: init_data,
                len: init_len,
            },
            &mut backend,
        )
    };
    if status == OK {
        unsafe { *out_backend = backend as i64 };
    }
    status
}

/// Executes a protobuf RPC through Anki's backend service dispatcher.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_run_method(
    backend: i64,
    service: u32,
    method: u32,
    input_data: *const u8,
    input_len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    if out_data.is_null() || out_len.is_null() {
        return INVALID_ARGUMENT;
    }
    let mut response = MankiAnkiOwnedBytes {
        data: ptr::null_mut(),
        len: 0,
    };
    let status = unsafe {
        manki_anki_backend_run(
            backend as *mut Backend,
            service,
            method,
            MankiAnkiBytes {
                data: input_data,
                len: input_len,
            },
            &mut response,
        )
    };
    unsafe {
        *out_data = response.data;
        *out_len = response.len;
    }
    status
}

/// Frees a response buffer handed to C by `manki_anki_run_method`.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_free_response(data: *mut u8, len: usize) {
    if !data.is_null() && len != 0 {
        // SAFETY: the pointer originated from a boxed slice in set_output().
        let _ = unsafe { Vec::from_raw_parts(data, len, len) };
    }
}

/// Releases the Anki backend instance.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_close_backend(backend: i64) {
    unsafe { manki_anki_backend_close(backend as *mut Backend) };
}

/// Syncs a Manki-owned local collection with AnkiWeb and returns decks as JSON.
///
/// This refuses a full upload and full-sync conflicts, so it cannot overwrite
/// AnkiWeb by choosing an upload direction. A normal rslib sync remains
/// bidirectional, matching Anki's standard sync semantics. `out_data` contains
/// a UTF-8 JSON array on success, or a UTF-8 error message on failure.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_fetch_decks(
    collection_path: *const c_char,
    endpoint: *const c_char,
    username: *const c_char,
    password: *const c_char,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    if collection_path.is_null()
        || endpoint.is_null()
        || username.is_null()
        || password.is_null()
        || out_data.is_null()
        || out_len.is_null()
    {
        return INVALID_ARGUMENT;
    }
    unsafe {
        *out_data = ptr::null_mut();
        *out_len = 0;
    }

    let result = (|| -> Result<Vec<u8>, String> {
        let collection_path = unsafe { c_string(collection_path) }?;
        let endpoint = unsafe { c_string(endpoint) }?;
        let username = unsafe { c_string(username) }?;
        let password = unsafe { c_string(password) }?;
        fetch_decks(&collection_path, &endpoint, &username, &password, None)
    })();

    match result {
        Ok(json) => {
            unsafe { set_output(json, out_data, out_len) };
            OK
        }
        Err(error) => {
            unsafe { set_output(error.into_bytes(), out_data, out_len) };
            FETCH_ERROR
        }
    }
}

/// Resolves a full-sync conflict in the direction explicitly selected by the
/// user, then returns the resulting decks as JSON.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_fetch_decks_full_sync(
    collection_path: *const c_char,
    endpoint: *const c_char,
    username: *const c_char,
    password: *const c_char,
    upload: bool,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    if collection_path.is_null()
        || endpoint.is_null()
        || username.is_null()
        || password.is_null()
        || out_data.is_null()
        || out_len.is_null()
    {
        return INVALID_ARGUMENT;
    }
    unsafe {
        *out_data = ptr::null_mut();
        *out_len = 0;
    }

    let result = (|| -> Result<Vec<u8>, String> {
        let collection_path = unsafe { c_string(collection_path) }?;
        let endpoint = unsafe { c_string(endpoint) }?;
        let username = unsafe { c_string(username) }?;
        let password = unsafe { c_string(password) }?;
        fetch_decks(
            &collection_path,
            &endpoint,
            &username,
            &password,
            Some(upload),
        )
    })();

    match result {
        Ok(json) => {
            unsafe { set_output(json, out_data, out_len) };
            OK
        }
        Err(error) => {
            unsafe { set_output(error.into_bytes(), out_data, out_len) };
            FETCH_ERROR
        }
    }
}

/// Returns deck scheduler counts from the local collection without syncing.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_load_decks(
    collection_path: *const c_char,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    review_operation(collection_path, out_data, out_len, deck_list)
}

/// Retrieves the first due card from a selected deck, rendered by rslib.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_get_next_card(
    collection_path: *const c_char,
    deck_id: i64,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    review_operation(collection_path, out_data, out_len, |backend| {
        select_deck(backend, deck_id)?;
        let queued = queued_cards(backend)?;
        let Some(card) = queued.cards.into_iter().next() else {
            return Ok(b"null".to_vec());
        };
        let card = card.card.ok_or("scheduler returned a card without an id")?;
        let card_id = card.id;
        let rendered: RenderCardResponse = call(
            backend,
            SERVICE_CARD_RENDERING,
            RENDER_EXISTING_CARD,
            RenderExistingCardRequest {
                card_id,
                browser: false,
                partial_render: false,
            },
        )?;
        let question = rendered_text(rendered.question_nodes);
        let answer = rendered_text(rendered.answer_nodes);
        let (question, question_audio) = extract_audio(backend, question, true)?;
        let (answer, answer_audio) = extract_audio(backend, answer, false)?;
        serde_json::to_vec(&json!({
            "id": card_id,
            "question": question,
            "answer": answer,
            "questionAudio": question_audio,
            "answerAudio": answer_audio,
            "flag": card.flags & 7,
        }))
        .map_err(|error| format!("could not encode card: {error}"))
    })
}

/// Re-fetches the queued card's states and delegates its scheduling to rslib.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_answer_card(
    collection_path: *const c_char,
    deck_id: i64,
    card_id: i64,
    rating: i32,
    milliseconds_taken: u32,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    review_operation(collection_path, out_data, out_len, |backend| {
        let rating = Rating::try_from(rating).map_err(|_| "invalid card rating")?;
        select_deck(backend, deck_id)?;
        let queued = queued_cards(backend)?;
        let queued_card = queued
            .cards
            .into_iter()
            .find(|item| item.card.as_ref().is_some_and(|card| card.id == card_id))
            .ok_or("the card is no longer due; refresh the deck and try again")?;
        let states = queued_card
            .states
            .ok_or("scheduler returned no scheduling states")?;
        let next_state = match rating {
            Rating::Again => states.again,
            Rating::Hard => states.hard,
            Rating::Good => states.good,
            Rating::Easy => states.easy,
        }
        .ok_or("scheduler returned an incomplete scheduling state")?;
        let _ = call::<_, anki_proto::collection::OpChanges>(
            backend,
            SERVICE_SCHEDULER,
            ANSWER_CARD,
            CardAnswer {
                card_id,
                current_state: states.current,
                new_state: Some(next_state),
                rating: rating as i32,
                answered_at_millis: now_millis(),
                milliseconds_taken,
            },
        )?;
        Ok(b"{}".to_vec())
    })
}

/// Applies one of Anki's standard colored flags to a card.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_set_card_flag(
    collection_path: *const c_char,
    card_id: i64,
    flag: u8,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    review_operation(collection_path, out_data, out_len, |backend| {
        if flag > 7 {
            return Err("invalid card flag".into());
        }
        let _ = call::<_, anki_proto::collection::OpChangesWithCount>(
            backend,
            SERVICE_CARDS,
            SET_FLAG,
            SetFlagRequest {
                card_ids: vec![card_id],
                flag: flag.into(),
            },
        )?;
        Ok(b"{}".to_vec())
    })
}

unsafe fn c_string(value: *const c_char) -> Result<String, String> {
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| "a string argument was not valid UTF-8".into())
}

fn fetch_decks(
    collection_path: &str,
    endpoint: &str,
    username: &str,
    password: &str,
    full_sync_upload: Option<bool>,
) -> Result<Vec<u8>, String> {
    let collection_path = PathBuf::from(collection_path);
    let parent = collection_path
        .parent()
        .ok_or("collection path has no parent directory")?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("could not create collection directory: {error}"))?;

    let backend = init_backend(&anki_proto::backend::BackendInit::default().encode_to_vec())
        .map_err(|error| format!("could not initialize Anki rslib: {error}"))?;
    let open_request = OpenCollectionRequest {
        collection_path: collection_path.display().to_string(),
        media_folder_path: media_folder(&collection_path)?.display().to_string(),
        media_db_path: media_database(&collection_path)?.display().to_string(),
    };
    call::<_, anki_proto::generic::Empty>(
        &backend,
        SERVICE_COLLECTION,
        OPEN_COLLECTION,
        open_request,
    )?;

    let result =
        fetch_decks_from_open_collection(&backend, endpoint, username, password, full_sync_upload);
    let close_result = call::<_, anki_proto::generic::Empty>(
        &backend,
        SERVICE_COLLECTION,
        CLOSE_COLLECTION,
        CloseCollectionRequest::default(),
    );
    let decks = result?;
    close_result?;
    Ok(decks)
}

fn review_operation(
    collection_path: *const c_char,
    out_data: *mut *mut u8,
    out_len: *mut usize,
    operation: impl FnOnce(&Backend) -> Result<Vec<u8>, String>,
) -> c_int {
    if collection_path.is_null() || out_data.is_null() || out_len.is_null() {
        return INVALID_ARGUMENT;
    }
    unsafe {
        *out_data = ptr::null_mut();
        *out_len = 0;
    }

    let result = (|| -> Result<Vec<u8>, String> {
        let collection_path = unsafe { c_string(collection_path) }?;
        with_open_collection(&collection_path, operation)
    })();
    match result {
        Ok(data) => {
            unsafe { set_output(data, out_data, out_len) };
            OK
        }
        Err(error) => {
            unsafe { set_output(error.into_bytes(), out_data, out_len) };
            FETCH_ERROR
        }
    }
}

fn with_open_collection(
    collection_path: &str,
    operation: impl FnOnce(&Backend) -> Result<Vec<u8>, String>,
) -> Result<Vec<u8>, String> {
    let collection_path = PathBuf::from(collection_path);
    let parent = collection_path
        .parent()
        .ok_or("collection path has no parent directory")?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("could not create collection directory: {error}"))?;
    let backend = init_backend(&anki_proto::backend::BackendInit::default().encode_to_vec())
        .map_err(|error| format!("could not initialize Anki rslib: {error}"))?;
    call::<_, anki_proto::generic::Empty>(
        &backend,
        SERVICE_COLLECTION,
        OPEN_COLLECTION,
        OpenCollectionRequest {
            collection_path: collection_path.display().to_string(),
            media_folder_path: media_folder(&collection_path)?.display().to_string(),
            media_db_path: media_database(&collection_path)?.display().to_string(),
        },
    )?;
    let result = operation(&backend);
    let close_result = call::<_, anki_proto::generic::Empty>(
        &backend,
        SERVICE_COLLECTION,
        CLOSE_COLLECTION,
        CloseCollectionRequest::default(),
    );
    let output = result?;
    close_result?;
    Ok(output)
}

fn select_deck(backend: &Backend, deck_id: i64) -> Result<(), String> {
    let _ = call::<_, anki_proto::collection::OpChanges>(
        backend,
        SERVICE_DECKS,
        SET_CURRENT_DECK,
        DeckId { did: deck_id },
    )?;
    Ok(())
}

fn queued_cards(backend: &Backend) -> Result<QueuedCards, String> {
    call(
        backend,
        SERVICE_SCHEDULER,
        GET_QUEUED_CARDS,
        GetQueuedCardsRequest {
            fetch_limit: 1,
            intraday_learning_only: false,
        },
    )
}

fn rendered_text(nodes: Vec<anki_proto::card_rendering::RenderedTemplateNode>) -> String {
    nodes
        .into_iter()
        .filter_map(|node| match node.value {
            Some(RenderedNodeValue::Text(text)) => Some(text),
            Some(RenderedNodeValue::Replacement(replacement)) => Some(replacement.current_text),
            None => None,
        })
        .collect()
}

fn extract_audio(
    backend: &Backend,
    text: String,
    question_side: bool,
) -> Result<(String, Vec<String>), String> {
    let extracted: ExtractAvTagsResponse = call(
        backend,
        SERVICE_CARD_RENDERING,
        EXTRACT_AV_TAGS,
        ExtractAvTagsRequest {
            text,
            question_side,
        },
    )?;
    let filenames = extracted
        .av_tags
        .into_iter()
        .filter_map(|tag| match tag.value {
            Some(AvTagValue::SoundOrVideo(filename)) => Some(filename),
            _ => None,
        })
        .collect();
    Ok((strip_play_markers(extracted.text), filenames))
}

fn strip_play_markers(mut text: String) -> String {
    const PREFIX: &str = "[anki:play:";
    while let Some(start) = text.find(PREFIX) {
        let Some(relative_end) = text[start..].find(']') else {
            break;
        };
        text.replace_range(start..=start + relative_end, "");
    }
    text
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn fetch_decks_from_open_collection(
    backend: &Backend,
    endpoint: &str,
    username: &str,
    password: &str,
    full_sync_upload: Option<bool>,
) -> Result<Vec<u8>, String> {
    let auth: SyncAuth = call(
        backend,
        SERVICE_SYNC,
        SYNC_LOGIN,
        SyncLoginRequest {
            username: username.into(),
            password: password.into(),
            endpoint: Some(endpoint.into()),
        },
    )?;
    let sync: SyncCollectionResponse = call(
        backend,
        SERVICE_SYNC,
        SYNC_COLLECTION,
        SyncCollectionRequest {
            auth: Some(auth.clone()),
            sync_media: true,
        },
    )?;

    match ChangesRequired::try_from(sync.required).unwrap_or(ChangesRequired::NoChanges) {
        ChangesRequired::NoChanges | ChangesRequired::NormalSync => {}
        ChangesRequired::FullDownload => {
            // A sync server may redirect a collection to another endpoint.
            // The full-download request must follow that endpoint, otherwise
            // it can receive a non-sync response that lacks rslib's required
            // `anki-original-size` header.
            let download_auth = SyncAuth {
                hkey: auth.hkey,
                endpoint: sync.new_endpoint.or(auth.endpoint),
                io_timeout_secs: auth.io_timeout_secs,
            };
            call::<_, anki_proto::generic::Empty>(
                backend,
                SERVICE_SYNC,
                FULL_UPLOAD_OR_DOWNLOAD,
                FullUploadOrDownloadRequest {
                    auth: Some(download_auth),
                    upload: false,
                    server_usn: Some(sync.server_media_usn),
                },
            )?;
        }
        ChangesRequired::FullUpload => {
            return Err("the server is empty; refusing a full upload while fetching decks".into())
        }
        ChangesRequired::FullSync => {
            let Some(upload) = full_sync_upload else {
                return Err(
                    "Anki requires a full-sync direction choice; refusing to overwrite either collection"
                        .into(),
                );
            };
            let full_sync_auth = SyncAuth {
                hkey: auth.hkey,
                endpoint: sync.new_endpoint.or(auth.endpoint),
                io_timeout_secs: auth.io_timeout_secs,
            };
            call::<_, anki_proto::generic::Empty>(
                backend,
                SERVICE_SYNC,
                FULL_UPLOAD_OR_DOWNLOAD,
                FullUploadOrDownloadRequest {
                    auth: Some(full_sync_auth),
                    upload,
                    server_usn: Some(sync.server_media_usn),
                },
            )?;
        }
    }

    wait_for_media_sync(backend)?;

    deck_list(backend)
}

fn wait_for_media_sync(backend: &Backend) -> Result<(), String> {
    loop {
        let status: MediaSyncStatusResponse = call(
            backend,
            SERVICE_SYNC,
            MEDIA_SYNC_STATUS,
            anki_proto::generic::Empty::default(),
        )?;
        if !status.active {
            return Ok(());
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
}

fn deck_list(backend: &Backend) -> Result<Vec<u8>, String> {
    let deck_names: DeckNames = call(
        backend,
        SERVICE_DECKS,
        GET_DECK_NAMES,
        GetDeckNamesRequest {
            skip_empty_default: false,
            include_filtered: false,
        },
    )?;
    let counts = call::<_, DeckTreeNode>(
        backend,
        SERVICE_DECKS,
        DECK_TREE,
        // DeckTreeRequest takes TimestampSecs; milliseconds make every card
        // appear to be scheduled far in the future.
        DeckTreeRequest { now: now_secs() },
    )?;
    let mut counts_by_deck = std::collections::HashMap::new();
    collect_deck_counts(&counts, true, &mut counts_by_deck);

    let decks = deck_names
        .entries
        .into_iter()
        .map(|deck| {
            let counts = counts_by_deck.get(&deck.id).copied().unwrap_or_default();
            json!({
                "id": deck.id,
                "name": deck.name,
                "new": counts.0,
                "learn": counts.1,
                "due": counts.2,
                // Parent counts already include descendants, so summing only
                // root-level decks gives the collection total without counting
                // nested decks twice.
                "contributesToBadge": counts.3,
            })
        })
        .collect::<Vec<_>>();
    serde_json::to_vec(&decks).map_err(|error| format!("could not encode deck list: {error}"))
}

/// DeckTreeNode count fields are already constrained by Anki's scheduler
/// limits, including limits inherited from parent decks. Flatten the tree so
/// the existing Swift deck list can retain its simple, alphabetical layout.
fn collect_deck_counts(
    node: &DeckTreeNode,
    is_root: bool,
    counts_by_deck: &mut std::collections::HashMap<i64, (u32, u32, u32, bool)>,
) {
    if node.deck_id != 0 {
        counts_by_deck.insert(
            node.deck_id,
            (node.new_count, node.learn_count, node.review_count, is_root),
        );
    }
    for child in &node.children {
        collect_deck_counts(child, node.deck_id == 0, counts_by_deck);
    }
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn call<Request: Message, Response: Message + Default>(
    backend: &Backend,
    service: u32,
    method: u32,
    request: Request,
) -> Result<Response, String> {
    let bytes = backend
        .run_service_method(service, method, &request.encode_to_vec())
        .map_err(decode_backend_error)?;
    Response::decode(bytes.as_slice()).map_err(|error| format!("invalid rslib response: {error}"))
}

fn decode_backend_error(bytes: Vec<u8>) -> String {
    match BackendError::decode(bytes.as_slice()) {
        Ok(error) if !error.message.is_empty() => error.message,
        Ok(error) => format!("Anki backend error kind {}", error.kind),
        Err(_) => "Anki backend returned an unreadable error".into(),
    }
}

fn media_folder(collection: &Path) -> Result<PathBuf, String> {
    let stem = collection
        .file_stem()
        .ok_or("collection path has no file name")?
        .to_string_lossy();
    Ok(collection.with_file_name(format!("{stem}.media")))
}

fn media_database(collection: &Path) -> Result<PathBuf, String> {
    let stem = collection
        .file_stem()
        .ok_or("collection path has no file name")?
        .to_string_lossy();
    Ok(collection.with_file_name(format!("{stem}.media.ad.db2")))
}

unsafe fn set_output(data: Vec<u8>, out_data: *mut *mut u8, out_len: *mut usize) {
    let len = data.len();
    if len == 0 {
        unsafe {
            *out_data = ptr::null_mut();
            *out_len = 0;
        }
        return;
    }

    let mut bytes = data.into_boxed_slice();
    let data = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    unsafe {
        *out_data = data;
        *out_len = len;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn demo_apkg_card_exposes_playable_question_audio() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/test.apkg");
        let test_dir = std::env::temp_dir().join(format!(
            "manki-audio-test-{}-{}",
            std::process::id(),
            now_millis()
        ));
        fs::create_dir_all(&test_dir).unwrap();
        let collection = test_dir.join("collection.anki2");
        let media = test_dir.join("collection.media");

        let cards = with_open_collection(collection.to_str().unwrap(), |backend| {
            let _: anki_proto::import_export::ImportResponse = call(
                backend,
                SERVICE_IMPORT_EXPORT,
                IMPORT_ANKI_PACKAGE,
                anki_proto::import_export::ImportAnkiPackageRequest {
                    package_path: fixture.display().to_string(),
                    options: None,
                },
            )?;
            deck_list(backend)
        })
        .unwrap();
        let decks: Value = serde_json::from_slice(&cards).unwrap();
        let deck_id = decks
            .as_array()
            .unwrap()
            .iter()
            .find(|deck| deck["new"].as_u64().unwrap_or_default() > 0)
            .unwrap()["id"]
            .as_i64()
            .unwrap();
        let collection_path = std::ffi::CString::new(collection.to_str().unwrap()).unwrap();
        let mut output = ptr::null_mut();
        let mut output_len = 0;
        let status = unsafe {
            manki_anki_get_next_card(
                collection_path.as_ptr(),
                deck_id,
                &mut output,
                &mut output_len,
            )
        };
        let card_bytes = unsafe { slice::from_raw_parts(output, output_len) };
        assert_eq!(status, OK, "{}", String::from_utf8_lossy(card_bytes));
        let card: Value = serde_json::from_slice(card_bytes).unwrap();
        unsafe { manki_anki_free_response(output, output_len) };

        assert_eq!(card["questionAudio"], json!(["de_glauben.mp3"]), "{card:#}");
        assert!(!card["question"].as_str().unwrap().contains("anki:play"));
        let sound = fs::read(media.join(card["questionAudio"][0].as_str().unwrap())).unwrap();
        assert!(
            sound.len() > 4_000,
            "audio attachment should contain playable data"
        );
        assert_eq!(&sound[..3], b"ID3", "audio attachment should be an MP3");

        fs::remove_dir_all(test_dir).unwrap();
    }
}
