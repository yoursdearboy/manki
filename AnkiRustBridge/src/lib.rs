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
    collection::{CloseCollectionRequest, OpenCollectionRequest},
    decks::{DeckNames, GetDeckNamesRequest},
    sync::{
        sync_collection_response::ChangesRequired, FullUploadOrDownloadRequest, SyncAuth,
        SyncCollectionRequest, SyncCollectionResponse, SyncLoginRequest,
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
const OPEN_COLLECTION: u32 = 0;
const CLOSE_COLLECTION: u32 = 1;
const SYNC_LOGIN: u32 = 3;
const SYNC_COLLECTION: u32 = 5;
const FULL_UPLOAD_OR_DOWNLOAD: u32 = 6;
const GET_DECK_NAMES: u32 = 13;

/// Initializes an Anki backend from a serialized `BackendInit` protobuf.
#[no_mangle]
pub unsafe extern "C" fn manki_anki_open_backend(
    init_data: *const u8,
    init_len: usize,
    out_backend: *mut i64,
) -> c_int {
    if out_backend.is_null() || (init_data.is_null() && init_len != 0) {
        return INVALID_ARGUMENT;
    }

    let init_bytes = if init_len == 0 {
        anki_proto::backend::BackendInit::default().encode_to_vec()
    } else {
        // SAFETY: the caller guarantees a valid buffer of init_len bytes.
        unsafe { slice::from_raw_parts(init_data, init_len) }.to_vec()
    };

    match init_backend(&init_bytes) {
        Ok(backend) => {
            // A Backend is immutable at this layer; rslib handles collection
            // access behind its own synchronization primitives.
            let handle = Box::into_raw(Box::new(backend)) as i64;
            // SAFETY: checked non-null above.
            unsafe { *out_backend = handle };
            OK
        }
        Err(_) => INITIALIZATION_ERROR,
    }
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
    if backend == 0
        || out_data.is_null()
        || out_len.is_null()
        || (input_data.is_null() && input_len != 0)
    {
        return INVALID_ARGUMENT;
    }

    // Make failure behavior deterministic for the caller.
    unsafe {
        *out_data = ptr::null_mut();
        *out_len = 0;
    }

    // SAFETY: the handle was produced by manki_anki_open_backend() and has
    // not been closed while this call is in flight.
    let backend = unsafe { &*(backend as *const Backend) };
    let input = if input_len == 0 {
        &[]
    } else {
        // SAFETY: validated by the C caller as documented in the header.
        unsafe { slice::from_raw_parts(input_data, input_len) }
    };

    match backend.run_service_method(service, method, input) {
        Ok(response) => {
            unsafe { set_output(response, out_data, out_len) };
            OK
        }
        Err(error) => {
            unsafe { set_output(error, out_data, out_len) };
            BACKEND_ERROR
        }
    }
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
    if backend != 0 {
        // SAFETY: ownership is transferred back exactly once by the caller.
        let _ = unsafe { Box::from_raw(backend as *mut Backend) };
    }
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
        fetch_decks(&collection_path, &endpoint, &username, &password)
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
) -> Result<Vec<u8>, String> {
    let collection_path = PathBuf::from(collection_path);
    let parent = collection_path
        .parent()
        .ok_or("collection path has no parent directory")?;
    fs::create_dir_all(parent).map_err(|error| format!("could not create collection directory: {error}"))?;

    let backend = init_backend(&anki_proto::backend::BackendInit::default().encode_to_vec())
        .map_err(|error| format!("could not initialize Anki rslib: {error}"))?;
    let open_request = OpenCollectionRequest {
        collection_path: collection_path.display().to_string(),
        media_folder_path: media_folder(&collection_path)?.display().to_string(),
        media_db_path: media_database(&collection_path)?.display().to_string(),
    };
    call::<_, anki_proto::generic::Empty>(&backend, SERVICE_COLLECTION, OPEN_COLLECTION, open_request)?;

    let result = fetch_decks_from_open_collection(&backend, endpoint, username, password);
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

fn fetch_decks_from_open_collection(
    backend: &Backend,
    endpoint: &str,
    username: &str,
    password: &str,
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
            sync_media: false,
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
                    // We only need collection data to list decks. Supplying a
                    // media USN starts a background media sync after the full
                    // download, which is unnecessary here and can fail
                    // independently of collection sync.
                    server_usn: None,
                },
            )?;
        }
        ChangesRequired::FullUpload => return Err("the server is empty; refusing a full upload while fetching decks".into()),
        ChangesRequired::FullSync => return Err("Anki requires a full-sync direction choice; refusing to overwrite either collection".into()),
    }

    let decks: DeckNames = call(
        backend,
        SERVICE_DECKS,
        GET_DECK_NAMES,
        GetDeckNamesRequest {
            skip_empty_default: false,
            include_filtered: false,
        },
    )?;
    let decks = decks
        .entries
        .into_iter()
        .map(|deck| json!({ "id": deck.id, "name": deck.name }))
        .collect::<Vec<_>>();
    serde_json::to_vec(&decks).map_err(|error| format!("could not encode deck list: {error}"))
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
