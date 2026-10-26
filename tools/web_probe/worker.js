// The probe's worker: what workers offer, decoding off the page, and uploads as the app's will run, one append at a
// time, resuming from the offset the server reports after a failed append.
import { rate } from "./rate.js";

const tasks = {
  features: () => ({
    "createImageBitmap in workers": typeof createImageBitmap === "function",
    "OPFS sync access in workers": typeof FileSystemSyncAccessHandle === "function",
  }),
  decode: ({ blob, ms }) => rate(ms, async () => (await createImageBitmap(blob)).close()),
  /** Uploads a file of `size` bytes to /upload/<name>; `read` reads each append into memory first, as encrypting it
   * needs, rather than sending the file's slice. The file is one `append`-sized part repeated, so that only what is
   * read from it takes memory. */
  async upload({ name, size, append, read }) {
    const part = new Blob([new Uint8Array(append)]);
    const file = new Blob(Array.from({ length: size / append }, () => part));
    const start = performance.now();
    let offset = 0;
    let resumes = 0;
    while (offset < size) {
      const slice = file.slice(offset, offset + append);
      const headers = {
        "content-type": "application/partial-upload",
        "upload-offset": `${offset}`,
        "upload-complete": offset + slice.size === size ? "?1" : "?0",
      };
      const body = read ? await slice.arrayBuffer() : slice;
      const response = await fetch(`/upload/${name}`, { method: "PATCH", headers, body }).catch(() => null);
      if (response?.ok) {
        offset += slice.size;
        continue;
      }
      if (++resumes > 3) throw new Error(`append at ${offset} failed: ${response?.status}`);
      offset = Number((await fetch(`/upload/${name}`, { method: "HEAD" })).headers.get("upload-offset"));
    }
    return { resumes, seconds: (performance.now() - start) / 1000 };
  },
};

onmessage = async ({ data: { id, task, input } }) => {
  try {
    postMessage({ id, output: await tasks[task](input) });
  } catch (error) {
    postMessage({ id, error: String(error) });
  }
};
