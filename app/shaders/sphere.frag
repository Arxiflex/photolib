// The panorama ray-caster (docs/10-client-app.md §4.4): each pixel's view ray, from yaw, pitch and field of view
// through a rectilinear, a stereographic (little planet) or an equidistant (fisheye) lens, becomes longitude and
// latitude, then a place in the picture: the GPano crop of an equirectangular or cylindrical panorama or a 3×2 cubemap,
// in one eye's part of the frame. Axes are FFmpeg v360's (x right, y down, z ahead), whose renders are the goldens.
// Filtered by hand, bilinear and wrapping round the sphere, so that no backend's sampler leaves a seam. Outside a
// partial panorama's crop, which the viewer's clamped views never show and a tile's pass leaves to the others, it is
// transparent, but a little planet stretches the crop's edges. As an image filter (ImageFilter.shader) its input is a
// player's texture laid out in the viewport's pixels (SpherePacking): the part of the frame in view, uInput, which the
// eye's next copy follows round the sphere, or only the cells in view, each in a slot of uGrid, which uCells finds, and
// the whole eye in slot 0 for any other.
#version 460 core
#include <flutter/runtime_effect.glsl>

// The engine's: the canvas', or as a filter its input's size in pixels.
uniform vec2 uSize;
// The size of the viewport, in pixels.
uniform vec2 uViewport;
// Yaw and pitch in radians, the lens' half-extent over the short side, and 1 for stereographic, 2 for fisheye.
uniform vec4 uView;
// The picture's left, top, width and height in the full panorama, as fractions.
uniform vec4 uCrop;
// The eye's left, top, width and height in the texture, as fractions.
uniform vec4 uEye;
// The frame's size in pixels, 1 for a cubemap or 2 for a cylinder, and the full panorama's width over its height.
uniform vec4 uTex;
// The slots across and down of a texture of packed cells, and 1 when it is one, 2 when it holds uInput; else 0, the
// whole frame.
uniform vec3 uGrid;
// The part of the frame that the texture holds: its left, top, width and height, as fractions.
uniform vec4 uInput;
uniform sampler2D uImage;
// Of packed cells, a cell's slot (red) in its row of the eye, and its row's cells (green); 16 × 8 bytes.
uniform sampler2D uCells;

out vec4 fragColor;

const float PI = 3.14159265358979;

vec3 ray(vec2 p) {
  vec3 d;
  if (uView.w > 0.5) {
    float r = length(p);
    float t = uView.w > 1.5 ? r : 2.0 * atan(r);
    d = vec3(r > 0.0 ? p / r * sin(t) : vec2(0.0), cos(t));
  } else {
    d = normalize(vec3(p, 1.0));
  }
  float cp = cos(uView.y), sp = sin(uView.y), cy = cos(uView.x), sy = sin(uView.x);
  d = vec3(d.x, d.y * cp - d.z * sp, d.y * sp + d.z * cp);
  return vec3(d.x * cy + d.z * sy, d.y, d.z * cy - d.x * sy);
}

// A byte of uCells at a cell of its 16 × 8.
float byte(float col, float row, bool green) {
  vec4 c = texture(uCells, vec2(col + 0.5, row + 0.5) / vec2(16.0, 8.0));
  return floor((green ? c.g : c.r) * 255.0 + 0.5);
}

// The frame at f, as fractions: in uInput, or in its cell's slot, else in slot 0, half a pixel within it.
vec4 frame(vec2 f) {
  if (uGrid.z < 0.5) return texture(uImage, f);
  if (uGrid.z > 1.5) {
    if (f.x < uInput.x) f.x += uEye.z;
    return texture(uImage, (f - uInput.xy) / uInput.zw);
  }
  vec2 e = clamp((f - uEye.xy) / uEye.zw, 0.0, 0.99999);
  float row = floor(e.y * 8.0);
  float cols = byte(0.0, row, true);
  float col = min(floor(e.x * cols), cols - 1.0);
  float slot = byte(col, row, false);
  vec2 at = slot > 0.5 ? vec2(e.x * cols - col, e.y * 8.0 - row) : e;
  vec2 inset = 0.5 * uGrid.xy / uSize;
  return texture(uImage, (vec2(mod(slot, uGrid.x), floor(slot / uGrid.x)) + clamp(at, inset, 1.0 - inset)) / uGrid.xy);
}

// The texel at whole coordinates t of the eye, of a face (cubemap) or of the whole crop.
vec4 texel(vec2 t, vec2 cell, vec2 size, bool wrap) {
  t.x = wrap ? mod(t.x, size.x) : clamp(t.x, 0.0, size.x - 1.0);
  t.y = clamp(t.y, 0.0, size.y - 1.0);
  return frame((uEye.xy * uTex.xy + cell * size + t + 0.5) / uTex.xy);
}

vec4 bilinear(vec2 uv, vec2 cell, vec2 size, bool wrap) {
  vec2 t = uv * size - 0.5;
  vec2 i = floor(t), f = t - i;
  return mix(
    mix(texel(i, cell, size, wrap), texel(i + vec2(1.0, 0.0), cell, size, wrap), f.x),
    mix(texel(i + vec2(0.0, 1.0), cell, size, wrap), texel(i + vec2(1.0), cell, size, wrap), f.x),
    f.y);
}

vec4 cube(vec3 d, vec2 eye) {
  vec3 a = abs(d);
  vec2 uv;
  float face;
  if (a.y >= a.x && a.y >= a.z) {
    face = d.y < 0.0 ? 2.0 : 3.0;
    uv = d.y < 0.0 ? vec2(-d.x, -d.z) / d.y : vec2(d.x, -d.z) / d.y;
  } else if (a.x >= a.z) {
    face = d.x > 0.0 ? 0.0 : 1.0;
    uv = vec2(-d.z, d.x > 0.0 ? d.y : -d.y) / d.x;
  } else {
    face = d.z > 0.0 ? 4.0 : 5.0;
    uv = vec2(d.x, d.z > 0.0 ? d.y : -d.y) / d.z;
  }
  return bilinear(uv * 0.5 + 0.5, vec2(mod(face, 3.0), floor(face / 3.0)), floor(eye / vec2(3.0, 2.0)), false);
}

void main() {
  vec2 at = FlutterFragCoord().xy;
  if (at.x > uViewport.x || at.y > uViewport.y) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 p = (at - uViewport * 0.5) / (min(uViewport.x, uViewport.y) * 0.5) * uView.z;
  // A fisheye sees no further than straight behind.
  if (uView.w > 1.5 && length(p) > PI) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 d = ray(p);
  vec2 eye = uEye.zw * uTex.xy;
  if (uTex.z > 0.5 && uTex.z < 1.5) {
    fragColor = cube(d, eye);
    return;
  }
  vec2 full = vec2(atan(d.x, d.z) / (2.0 * PI), asin(clamp(d.y, -1.0, 1.0)) / PI) + 0.5;
  // Down a cylinder, the tangent of the latitude.
  if (uTex.z > 1.5) full.y = 0.5 + d.y / max(length(d.xz), 1e-6) * uTex.w / (2.0 * PI);
  bool whole = uCrop.z > 0.999;
  vec2 uv = vec2(fract(full.x - uCrop.x) / uCrop.z, (full.y - uCrop.y) / uCrop.w);
  if (abs(uView.w - 1.0) > 0.5 && (uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)) {
    fragColor = vec4(0.0);
    return;
  }
  // Past a partial panorama's sides, the nearer side.
  if (uv.x > 1.0) uv.x = uv.x > 0.5 + 0.5 / uCrop.z ? 0.0 : 1.0;
  fragColor = bilinear(uv, vec2(0.0), eye, whole);
}
