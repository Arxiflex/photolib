#![no_main]

libfuzzer_sys::fuzz_target!(|data: &[u8]| photolib_kernel_fuzz::edit_recipe(data));
