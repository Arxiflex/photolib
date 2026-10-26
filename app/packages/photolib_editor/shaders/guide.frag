// Pass 1 of the guide: each cell's mean log2 luminance over 8×8 taps of the proxy.
#version 460 core
#include <flutter/runtime_effect.glsl>
#include "common.glsl"

uniform vec2 uProxy;
uniform vec2 uCells;
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
  vec2 cell = floor(FlutterFragCoord().xy);
  float sum = 0.0;
  for (int b = 0; b < 8; b++) {
    float y = min(floor((cell.y + (float(b) + 0.5) / 8.0) * uProxy.y / uCells.y), uProxy.y - 1.0);
    for (int a = 0; a < 8; a++) {
      float x = min(floor((cell.x + (float(a) + 0.5) / 8.0) * uProxy.x / uCells.x), uProxy.x - 1.0);
      sum += logLuminance(decode(texture(uImage, (vec2(x, y) + 0.5) / uProxy).rgb));
    }
  }
  fragColor = packLog(sum / 64.0);
}
