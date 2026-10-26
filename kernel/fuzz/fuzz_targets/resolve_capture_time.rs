#![no_main]

libfuzzer_sys::fuzz_target!(|data: &[u8]| photolib_kernel_fuzz::resolve_capture_time(data));
