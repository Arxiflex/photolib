//! The C ABI of photolib-kernel, for dart:ffi and other foreign callers: the one crate where unsafe code is allowed.
//! Every function returns an encoded `CallResponse` in a buffer that the caller frees with `photolib_kernel_free`.
//! A panic cannot unwind into the caller, which would abort the app: each function catches it, and a call that
//! panicked fails with kernel.panic (`CALL_ERROR_CODE_PANIC`).
#![allow(unsafe_code)]

use photolib_kernel::{Keyring, Stream, panicked};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::{ptr, slice};

/// Bytes owned by the kernel.
#[repr(C)]
pub struct Buffer {
    data: *mut u8,
    length: usize,
}

impl From<Vec<u8>> for Buffer {
    fn from(bytes: Vec<u8>) -> Self {
        let length = bytes.len();
        Buffer {
            data: Box::into_raw(bytes.into_boxed_slice()).cast(),
            length,
        }
    }
}

/// # Safety
/// `data` points to `length` readable bytes, or `length` is 0.
unsafe fn bytes<'a>(data: *const u8, length: usize) -> &'a [u8] {
    if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(data, length) }
    }
}

/// Runs `run`, or `or` if it panicked.
fn guard<T>(run: impl FnOnce() -> T, or: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(run)).unwrap_or_else(|_| or())
}

/// Runs a kernel function, as `photolib_kernel::call`.
///
/// # Safety
/// `request` points to `length` readable bytes, or `length` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_call(method_id: u32, request: *const u8, length: usize) -> Buffer {
    let request = unsafe { bytes(request, length) };
    guard(|| photolib_kernel::call(method_id, request), panicked).into()
}

/// Opens a stream, as `Stream::open`; `photolib_kernel_stream_finish` frees it.
///
/// # Safety
/// `request` points to `length` readable bytes, or `length` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_stream_open(method_id: u32, request: *const u8, length: usize) -> *mut Stream {
    let request = unsafe { bytes(request, length) };
    let stream = guard(|| Stream::open(method_id, request), Stream::panicked);
    Box::into_raw(Box::new(stream))
}

/// Creates an empty keyring, for functions that take key handles; `photolib_kernel_keyring_free` frees it. Null if
/// that panicked.
#[unsafe(no_mangle)]
pub extern "C" fn photolib_kernel_keyring_new() -> *mut Keyring {
    guard(|| Box::into_raw(Box::default()), ptr::null_mut)
}

/// Runs a kernel function with the keys of a keyring, as `Keyring::call`.
///
/// # Safety
/// `keyring` is live, and `request` points to `length` readable bytes, or `length` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_keyring_call(
    keyring: *mut Keyring,
    method_id: u32,
    request: *const u8,
    length: usize,
) -> Buffer {
    let (keyring, request) = unsafe { (&mut *keyring, bytes(request, length)) };
    guard(|| keyring.call(method_id, request), panicked).into()
}

/// Opens a stream with the keys of a keyring, as `Keyring::open_stream`; `photolib_kernel_stream_finish` frees it.
///
/// # Safety
/// `keyring` is live, and `request` points to `length` readable bytes, or `length` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_keyring_stream_open(
    keyring: *const Keyring,
    method_id: u32,
    request: *const u8,
    length: usize,
) -> *mut Stream {
    let (keyring, request) = unsafe { (&*keyring, bytes(request, length)) };
    let stream = guard(|| keyring.open_stream(method_id, request), Stream::panicked);
    Box::into_raw(Box::new(stream))
}

/// Zeroizes every key of a keyring and frees it.
///
/// # Safety
/// `keyring` came from `photolib_kernel_keyring_new` and is not used again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_keyring_free(keyring: *mut Keyring) {
    let keyring = unsafe { Box::from_raw(keyring) };
    guard(|| drop(keyring), || ());
}

/// Pushes input into a stream, as `Stream::push`; after a panic, every later step fails with kernel.panic too.
///
/// # Safety
/// `stream` is open, and `input` points to `length` readable bytes, or `length` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_stream_push(stream: *mut Stream, input: *const u8, length: usize) -> Buffer {
    let (stream, input) = unsafe { (&mut *stream, bytes(input, length)) };
    let pushed = catch_unwind(AssertUnwindSafe(|| stream.push(input)));
    pushed
        .unwrap_or_else(|_| {
            let broken = std::mem::replace(stream, Stream::panicked());
            guard(|| drop(broken), || ());
            panicked()
        })
        .into()
}

/// Finishes a stream, as `Stream::finish`, and frees it.
///
/// # Safety
/// `stream` is open; it is not used again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_stream_finish(stream: *mut Stream) -> Buffer {
    let stream = unsafe { Box::from_raw(stream) };
    guard(|| stream.finish(), panicked).into()
}

/// Frees a buffer the kernel returned.
///
/// # Safety
/// `buffer` came from this library and is not used again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn photolib_kernel_free(buffer: Buffer) {
    let bytes = unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(buffer.data, buffer.length)) };
    guard(|| drop(bytes), || ());
}

#[cfg(test)]
mod tests {
    use super::*;
    use photolib_kernel::proto::kernel::v1::Method;
    use photolib_kernel::{PANIC_PROBE, panicked};

    fn take(buffer: Buffer) -> Vec<u8> {
        let bytes = unsafe { bytes(buffer.data, buffer.length) }.to_vec();
        unsafe { photolib_kernel_free(buffer) };
        bytes
    }

    /// Each entry point returns kernel.panic for a panic, which would otherwise abort the app, and the kernel and its
    /// keyring go on working.
    #[test]
    fn a_panic_fails_only_its_call() {
        let parse = Method::ParseQuery as u32;
        unsafe {
            assert_eq!(take(photolib_kernel_call(PANIC_PROBE, ptr::null(), 0)), panicked());
            let keyring = photolib_kernel_keyring_new();
            let call = |method| take(photolib_kernel_keyring_call(keyring, method, ptr::null(), 0));
            assert_eq!(call(PANIC_PROBE), panicked());
            for stream in [
                photolib_kernel_stream_open(PANIC_PROBE, ptr::null(), 0),
                photolib_kernel_keyring_stream_open(keyring, PANIC_PROBE, ptr::null(), 0),
            ] {
                assert_eq!(take(photolib_kernel_stream_push(stream, ptr::null(), 0)), panicked());
                assert_eq!(take(photolib_kernel_stream_finish(stream)), panicked());
            }
            assert_eq!(call(parse), photolib_kernel::call(parse, &[]));
            photolib_kernel_keyring_free(keyring);
        }
    }
}
