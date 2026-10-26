// Calls into the kernel's module from JavaScript, where a trap can be caught: WebAssembly code, such as what dart2wasm
// compiles, cannot catch one even after it passed through JavaScript. Returns undefined when the module trapped.
// tools/kernel/wasm.sh ships it as photolib_kernel_guard.js beside the module.
export function guard(target, method, ...args) {
  try {
    return target[method](...args);
  } catch {
    return undefined;
  }
}
