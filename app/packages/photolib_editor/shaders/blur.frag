// Passes 2 and 3 of the guide: a Gaussian of σ = 1.5 cells along uStep, clamped at the edges.
#version 460 core
#include <flutter/runtime_effect.glsl>
#include "common.glsl"

uniform vec2 uCells;
uniform vec2 uStep;
uniform sampler2D uGuide;

out vec4 fragColor;

float at(vec2 cell) {
  return unpackLog(texture(uGuide, (clamp(cell, vec2(0.0), uCells - 1.0) + 0.5) / uCells));
}

float pair(vec2 cell, float k) {
  return at(cell - k * uStep) + at(cell + k * uStep);
}

void main() {
  vec2 cell = floor(FlutterFragCoord().xy);
  float sum = 0.26656 * at(cell);
  sum += 0.2134445 * pair(cell, 1.0);
  sum += 0.1095861 * pair(cell, 2.0);
  sum += 0.036075 * pair(cell, 3.0);
  sum += 0.0076144 * pair(cell, 4.0);
  fragColor = packLog(sum);
}
