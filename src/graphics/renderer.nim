import std/[strutils]
import ../core/sdf_ast
import ../compiler/glsl_gen
import camera

type
  ViewMode* = enum vmShaded, vmZebra, vmHeatmap, vmNormals
  RenderMetrics* = object
    fps*: float
    scriptMs*, glslMs*: float
    nodeCount*: int
  Renderer* = object
    width*, height*: int
    fbo*, texture*, program*: uint32
    viewMode*: ViewMode
    ortho*: bool
    stepScale*: float
    shaderSource*: string
    metrics*: RenderMetrics
    initialized*: bool

proc initRenderer*(width = 1280, height = 720): Renderer =
  Renderer(width: width, height: height, fbo: 0, texture: 0, program: 0,
           viewMode: vmShaded, ortho: false, stepScale: 1.0,
           initialized: false)

const RAYMARCH_TEMPLATE* = """
#version 430
in vec2 v_uv;
out vec4 fragColor;
uniform vec2 u_resolution;
uniform vec3 u_cameraPos;
uniform vec3 u_cameraTarget;
uniform int u_viewMode;
uniform float u_stepScale;
uniform float u_ortho;
uniform float u_orthoScale;
uniform float u_time;

float softShadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
  float res = 1.0;
  float t = mint;
  for (int i = 0; i < 64; i++) {
    vec4 h = mapScene(ro + rd * t);
    res = min(res, k * h.x / t);
    t += clamp(h.x, 0.02, 0.25);
    if (h.x < 0.001 || t > maxt) break;
  }
  return clamp(res, 0.0, 1.0);
}

float ambientOcclusion(vec3 p, vec3 n) {
  float occ = 0.0;
  float scale = 1.0;
  for (int i = 1; i <= 5; i++) {
    float h = 0.03 * float(i);
    float d = mapScene(p + n * h).x;
    occ += (h - d) * scale;
    scale *= 0.75;
  }
  return clamp(1.0 - occ * 1.5, 0.0, 1.0);
}

vec3 calcNormal(vec3 p) {
  const float h = 0.0005;
  const vec2 k = vec2(1.0, -1.0);
  return normalize(k.xyy * mapScene(p + k.xyy * h).x +
                   k.yyx * mapScene(p + k.yyx * h).x +
                   k.yxy * mapScene(p + k.yxy * h).x +
                   k.xxx * mapScene(p + k.xxx * h).x);
}

vec3 infiniteGrid(vec3 ro, vec3 rd) {
  float t = -ro.y / rd.y;
  if (t < 0.0) return vec3(0.0);
  vec3 p = ro + rd * t;
  vec2 g = abs(fract(p.xz - 0.5) - 0.5) / fwidth(p.xz);
  float line = 1.0 - min(min(g.x, g.y), 1.0);
  vec3 minor = mix(vec3(0.035), vec3(0.12), line);
  vec2 g10 = abs(fract(p.xz * 0.1 - 0.5) - 0.5) / fwidth(p.xz * 0.1);
  float major = 1.0 - min(min(g10.x, g10.y), 1.0);
  vec3 majorColor = mix(minor, vec3(0.22), major);
  if (abs(p.x) < 0.025) majorColor = vec3(0.75, 0.12, 0.12);
  if (abs(p.z) < 0.025) majorColor = vec3(0.12, 0.65, 0.20);
  float fade = exp(-0.0008 * t * t);
  return majorColor * fade;
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution) / u_resolution.y;
  vec3 forward = normalize(u_cameraTarget - u_cameraPos);
  vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(right, forward);
  vec3 ro = u_cameraPos;
  vec3 rd = normalize(forward + right * uv.x + up * uv.y);
  if (u_ortho > 0.5) {
    ro += right * uv.x * u_orthoScale + up * uv.y * u_orthoScale;
  }
  float t = 0.0;
  vec4 hit = vec4(1000.0);
  for (int i = 0; i < 256; i++) {
    hit = mapScene(ro + rd * t);
    float step = hit.x * u_stepScale;
    if (abs(step) < 0.0005 || t > 1000.0) break;
    t += max(step, 0.0005);
  }
  vec3 color = vec3(0.025, 0.030, 0.040);
  if (t < 1000.0 && hit.x < 0.002) {
    vec3 p = ro + rd * t;
    vec3 n = calcNormal(p);
    vec3 lightDir = normalize(vec3(-0.5, 0.8, 0.6));
    float diff = max(dot(n, lightDir), 0.0);
    float ao = ambientOcclusion(p, n);
    float shadow = softShadow(p + n * 0.01, lightDir, 0.02, 30.0, 16.0);
    if (u_viewMode == 1) {
      float stripe = smoothstep(0.35, 0.65, sin(p.y * 0.75 + n.y * 4.0));
      color = mix(vec3(0.10, 0.12, 0.16), vec3(0.85, 0.90, 0.95), stripe);
    } else if (u_viewMode == 2) {
      color = mix(vec3(0.05, 0.25, 0.80), vec3(1.0, 0.15, 0.05),
                  smoothstep(-5.0, 5.0, hit.x));
    } else if (u_viewMode == 3) {
      color = n * 0.5 + 0.5;
    } else {
      vec3 base = hit.yzw;
      color = base * (0.22 + diff * 0.78 * shadow) * ao;
    }
  } else {
    color = infiniteGrid(ro, rd);
  }
  fragColor = vec4(pow(color, vec3(0.4545)), 1.0);
}
"""

proc buildFragmentSource*(arena: SDFArena): string =
  let mapProgram = generateMap(arena)
  let mapSource = mapProgram.source.replace("#version 430\n", "")
                              .replace("in vec2 v_uv;\n", "")
                              .replace("out vec4 fragColor;\n", "")
  RAYMARCH_TEMPLATE & "\n" & mapSource
