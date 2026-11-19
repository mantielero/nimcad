import ../src/core/sdf_ast
import ../src/compiler/glsl_gen
import ../src/graphics/mesher
import strutils

var arena = initSDFArena()
let base = arena.sphere(10.0)
let boxId = arena.box(8.0, 8.0, 8.0)
let root = arena.opUnion(base, boxId)
arena.root = root

doAssert arena.nodes.len == 3
let glsl = generateMap(arena)
doAssert glsl.source.find("vec4 mapScene") >= 0
doAssert glsl.source.find("sdSphere") >= 0
let mesh = exportBinarySTL(arena, "/tmp/nimcad_test.stl",
                           AABB(lo: vec3(-12, -12, -12),
                                hi: vec3(12, 12, 12)), 2.0)
doAssert mesh.triangles >= 0
