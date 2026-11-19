import std/strutils
import ../src/core/sdf_ast
import ../src/core/script_engine
import ../src/compiler/glsl_gen
import ../src/graphics/mesher
import ../src/graphics/renderer

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

let example = evalLineScript(readFile("examples/01_hola_mundo.nims"))
doAssert example.errors.len == 0, $example.errors
doAssert example.root >= 0
doAssert example.arena.nodes.len == 5
doAssert example.arena.nodes[example.root].kind == nkColor
let smooth = example.arena.nodes[example.root].a
doAssert example.arena.nodes[smooth].kind == nkSmoothUnion
let translatedBox = example.arena.nodes[smooth].b
doAssert example.arena.nodes[translatedBox].kind == nkTranslate
doAssert example.arena.nodes[translatedBox].offset.x == 12.0

let fragment = buildFragmentSource(example.arena)
doAssert fragment.find("#version 430") == 0
doAssert fragment.find("vec4 mapScene") < fragment.find("float softShadow")
doAssert fragment.find("vec3 p_2 = p - vec3(12.000000") >= 0

let invalidScript = evalLineScript("render(missingShape())")
doAssert invalidScript.errors.len == 1
doAssert invalidScript.root < 0
