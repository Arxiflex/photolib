// The develop adjustments of kernel/src/develop.rs in one pass, on a tile at uOrigin of an image of uFull pixels.
#version 460 core
#include <flutter/runtime_effect.glsl>
#include "common.glsl"

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec2 uFull;
uniform vec2 uCells;
uniform vec3 uGains;
// Contrast, clarity, saturation and the LUT's size (0 for none).
uniform vec4 uTone;
uniform sampler2D uImage;
uniform sampler2D uGuide;
// The LUT as an atlas of uTone.w² × uTone.w entries (blue slices side by side), high bytes above low bytes.
uniform sampler2D uLut;

out vec4 fragColor;

float guideAt(vec2 cell) {
  return unpackLog(texture(uGuide, (clamp(cell, vec2(0.0), uCells - 1.0) + 0.5) / uCells));
}

vec3 lutAt(float r, float g, float b) {
  float n = uTone.w;
  vec2 size = vec2(n * n, 2.0 * n);
  vec2 at = vec2(b * n + r, g) + 0.5;
  vec3 hi = texture(uLut, at / size).rgb;
  vec3 lo = texture(uLut, (at + vec2(0.0, n)) / size).rgb;
  return vec3(unpack16(vec2(hi.r, lo.r)), unpack16(vec2(hi.g, lo.g)), unpack16(vec2(hi.b, lo.b)));
}

vec3 lut(vec3 v) {
  vec3 p = clamp(v, 0.0, 1.0) * (uTone.w - 1.0);
  vec3 i = min(floor(p), uTone.w - 2.0);
  vec3 f = p - i;
  vec3 c000 = lutAt(i.r, i.g, i.b);
  vec3 c100 = lutAt(i.r + 1.0, i.g, i.b);
  vec3 c010 = lutAt(i.r, i.g + 1.0, i.b);
  vec3 c110 = lutAt(i.r + 1.0, i.g + 1.0, i.b);
  vec3 c001 = lutAt(i.r, i.g, i.b + 1.0);
  vec3 c101 = lutAt(i.r + 1.0, i.g, i.b + 1.0);
  vec3 c011 = lutAt(i.r, i.g + 1.0, i.b + 1.0);
  vec3 c111 = lutAt(i.r + 1.0, i.g + 1.0, i.b + 1.0);
  vec3 r00 = c000 + (c100 - c000) * f.r;
  vec3 r10 = c010 + (c110 - c010) * f.r;
  vec3 r01 = c001 + (c101 - c001) * f.r;
  vec3 r11 = c011 + (c111 - c011) * f.r;
  vec3 plane0 = r00 + (r10 - r00) * f.g;
  vec3 plane1 = r01 + (r11 - r01) * f.g;
  return plane0 + (plane1 - plane0) * f.b;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec3 c = decode(texture(uImage, pixel / uSize).rgb);

  vec2 uv = (uOrigin + pixel) * uCells / uFull - 0.5;
  vec2 cell = floor(uv);
  vec2 f = uv - cell;
  float g0 = guideAt(cell);
  g0 += (guideAt(cell + vec2(1.0, 0.0)) - g0) * f.x;
  float g1 = guideAt(cell + vec2(0.0, 1.0));
  g1 += (guideAt(cell + vec2(1.0, 1.0)) - g1) * f.x;
  float detail = logLuminance(c) - (g0 + (g1 - g0) * f.y);

  c = c * uGains * exp2(uTone.y * detail / (1.0 + abs(detail)));
  float y = luminance(c);
  c = y + (c - y) * (1.0 + uTone.z);
  vec3 v = encode(clamp(c, 0.0, 1.0));
  v += uTone.x * (v * v * (3.0 - 2.0 * v) - v);
  if (uTone.w > 0.0) {
    v = lut(v);
  }
  fragColor = vec4(clamp(v, 0.0, 1.0), 1.0);
}
