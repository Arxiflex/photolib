//! The kernel on the web: photolib-kernel as WebAssembly through wasm-bindgen, one ES module for Flutter web and the
//! viewer (`tools/kernel/wasm.sh` builds it). Single-threaded, so pages need no cross-origin isolation. Every function
//! returns an encoded `CallResponse`.
#![forbid(unsafe_code)]

use wasm_bindgen::prelude::wasm_bindgen;
use zeroize::Zeroize;

/// Runs a kernel function, as `photolib_kernel::call`.
#[wasm_bindgen]
pub fn call(method_id: u32, request: &[u8]) -> Vec<u8> {
    photolib_kernel::call(method_id, request)
}

/// Opens a stream, as `photolib_kernel::Stream::open`.
#[wasm_bindgen(js_name = openStream)]
pub fn open_stream(method_id: u32, request: &[u8]) -> Stream {
    Stream(photolib_kernel::Stream::open(method_id, request))
}

/// Creates an empty keyring, for functions that take key handles.
#[wasm_bindgen(js_name = newKeyring)]
pub fn new_keyring() -> Keyring {
    Keyring(photolib_kernel::Keyring::default())
}

/// Keys that never leave the module, named by handles; `free()` zeroizes them.
#[wasm_bindgen]
pub struct Keyring(photolib_kernel::Keyring);

#[wasm_bindgen]
impl Keyring {
    /// Runs a kernel function with this keyring's keys. The request, which may hold a key being imported, is zeroized.
    pub fn call(&mut self, method_id: u32, mut request: Vec<u8>) -> Vec<u8> {
        let response = self.0.call(method_id, &request);
        request.zeroize();
        response
    }

    #[wasm_bindgen(js_name = openStream)]
    pub fn open_stream(&self, method_id: u32, request: &[u8]) -> Stream {
        Stream(self.0.open_stream(method_id, request))
    }
}

/// A streaming call; finishing it frees it.
#[wasm_bindgen]
pub struct Stream(photolib_kernel::Stream);

#[wasm_bindgen]
impl Stream {
    pub fn push(&mut self, input: &[u8]) -> Vec<u8> {
        self.0.push(input)
    }

    pub fn finish(self) -> Vec<u8> {
        self.0.finish()
    }
}
