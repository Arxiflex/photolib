// The definitions the three shaders share, as kernel/src/develop.rs writes them. Values stored between passes are
// 16-bit, in two 8-bit channels, because the targets of toImage are 8 bits per channel on most backends.
precision highp float;

const float kDarkest = -12.0;

float decode1(float v) {
  return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

vec3 decode(vec3 v) {
  return vec3(decode1(v.r), decode1(v.g), decode1(v.b));
}

float encode1(float l) {
  return l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1.0 / 2.4) - 0.055;
}

vec3 encode(vec3 l) {
  return vec3(encode1(l.r), encode1(l.g), encode1(l.b));
}

float luminance(vec3 c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

float logLuminance(vec3 c) {
  return log2(max(luminance(c), exp2(kDarkest)));
}

float unpack16(vec2 hiLo) {
  vec2 bytes = floor(hiLo * 255.0 + 0.5);
  return (bytes.x * 256.0 + bytes.y) / 65535.0;
}

// A log2 luminance in [kDarkest, 0] as 16 bits.
vec4 packLog(float l) {
  float v = floor(clamp(l / -kDarkest + 1.0, 0.0, 1.0) * 65535.0 + 0.5);
  float hi = floor(v / 256.0);
  return vec4(hi / 255.0, (v - hi * 256.0) / 255.0, 0.0, 1.0);
}

float unpackLog(vec4 texel) {
  return (unpack16(texel.rg) - 1.0) * -kDarkest;
}
