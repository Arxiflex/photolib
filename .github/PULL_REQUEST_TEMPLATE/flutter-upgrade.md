## Flutter upgrade

<!-- Use this description when the change moves the version in app/.fvmrc (see docs/dev/flutter.md). Tick a gate only with the evidence linked beside it. -->

- [ ] Every test layer is green on the new version.
- [ ] The performance suite is within 10 % of the current version on the reference devices (frame times, startup, RSS, 10-minute soak).
- [ ] Goldens pass, including panorama shader filtering, video textures, the HDR platform-view transition and text.
- [ ] At least 3 low-end Android devices (Redmi 9 class, Android Go) were checked for ANRs and memory.
- [ ] The renderer matrix was checked: Impeller Vulkan and the GLES fallback, Vulkan on old Windows and Linux iGPUs, Metal.
- [ ] The new version ran for at least 2 weeks on the beta channel with the weekly beta run green.
