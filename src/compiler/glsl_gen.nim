import strutils
import ../core/sdf_ast
import glsl_templates

type GLSLProgram* = object
  source*, uniforms*: string
  nodeCount*: int

proc fstr(v: float): string =
  let s = formatFloat(v, ffDecimal, 6)
  if s.contains('.'): s else: s & ".0"

proc glVec(v: Vec3): string =
  "vec3(" & v.x.fstr & ", " & v.y.fstr & ", " & v.z.fstr & ")"

proc rotatePoint(v: Vec3): string =
  "p.yzx"

proc generateMap*(arena: SDFArena): GLSLProgram =
  var body = newStringOfCap(arena.nodes.len * 180)
  var memo = newSeq[string](arena.nodes.len)
  var uniformNames = ""

  proc emit(nodeId: int, parentVar: string): tuple[distance, color: string] =
    if memo[nodeId].len > 0:
      return (distance: "d_" & $nodeId, color: "c_" & $nodeId)

    let node = arena.nodes[nodeId]
    let pv = if nodeId == arena.root: "p" else: parentVar

    case node.kind
    of nkSphere:
      body.add "  float d_" & $nodeId & " = sdSphere(" & pv & ", " & node.radius.fstr & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkBox:
      body.add "  float d_" & $nodeId & " = sdBox(" & pv & ", " & node.size.glVec & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkRoundBox:
      body.add "  float d_" & $nodeId & " = sdRoundBox(" & pv & ", " & node.size.glVec & ", " & node.radius.fstr & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkTorus:
      body.add "  float d_" & $nodeId & " = sdTorus(" & pv & ", " & node.majorRadius.fstr & ", " & node.minorRadius.fstr & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkCylinder:
      body.add "  float d_" & $nodeId & " = sdCylinder(" & pv & ", " & node.radius.fstr & ", " & node.height.fstr & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkCapsule:
      body.add "  float d_" & $nodeId & " = sdCapsule(" & pv & ", " & node.pointA.glVec & ", " & node.pointB.glVec & ", " & node.radius.fstr & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkEllipsoid:
      body.add "  float d_" & $nodeId & " = sdEllipsoid(" & pv & ", " & node.size.glVec & ");\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    of nkTranslate:
      discard emit(node.a, pv)
      let childP = "p_" & $nodeId
      body.insert("  vec3 " & childP & " = " & pv & " - " & node.offset.glVec & ";\n", body.len)
      # Translation is represented as transformed input for the child; emit above is reparable in the body order.
      body.add "  float d_" & $nodeId & " = d_" & $node.a & ";\n"
      body.add "  vec3 c_" & $nodeId & " = c_" & $node.a & ";\n"
    of nkScale:
      discard emit(node.a, pv)
      body.add "  float d_" & $nodeId & " = d_" & $node.a & " * " & node.scale.fstr & ";\n"
      body.add "  vec3 c_" & $nodeId & " = c_" & $node.a & ";\n"
    of nkUnion, nkSubtraction, nkIntersection,
       nkSmoothUnion, nkSmoothSubtraction, nkSmoothIntersection:
      let da = emit(node.a, pv)
      let db = emit(node.b, pv)
      var distanceExpr: string
      case node.kind
      of nkUnion: distanceExpr = "opUnion(" & da.distance & ", " & db.distance & ")"
      of nkSubtraction: distanceExpr = "opSubtraction(" & da.distance & ", " & db.distance & ")"
      of nkIntersection: distanceExpr = "opIntersection(" & da.distance & ", " & db.distance & ")"
      of nkSmoothUnion: distanceExpr = "opSmoothUnion(" & da.distance & ", " & db.distance & ", " & node.thickness.fstr & ")"
      of nkSmoothSubtraction: distanceExpr = "opSmoothSubtraction(" & da.distance & ", " & db.distance & ", " & node.thickness.fstr & ")"
      of nkSmoothIntersection: distanceExpr = "opSmoothIntersection(" & da.distance & ", " & db.distance & ", " & node.thickness.fstr & ")"
      else: distanceExpr = da.distance
      body.add "  float d_" & $nodeId & " = " & distanceExpr & ";\n"
      body.add "  vec3 c_" & $nodeId & " = (" & da.distance & " <= " & db.distance & ") ? " & da.color & " : " & db.color & ";\n"
    of nkRound:
      discard emit(node.a, pv)
      body.add "  float d_" & $nodeId & " = d_" & $node.a & " - " & node.thickness.fstr & ";\n"
      body.add "  vec3 c_" & $nodeId & " = c_" & $node.a & ";\n"
    of nkOnion:
      discard emit(node.a, pv)
      body.add "  float d_" & $nodeId & " = abs(d_" & $node.a & ") - " & node.thickness.fstr & ";\n"
      body.add "  vec3 c_" & $nodeId & " = c_" & $node.a & ";\n"
    of nkColor:
      discard emit(node.a, pv)
      body.add "  float d_" & $nodeId & " = d_" & $node.a & ";\n"
      body.add "  vec3 c_" & $nodeId & " = " & node.material.glVec & ";\n"
    else:
      if node.a >= 0:
        discard emit(node.a, pv)
      body.add "  float d_" & $nodeId & " = " & (if node.a >= 0: "d_" & $node.a else: "0.0") & ";\n"
      body.add "  vec3 c_" & $nodeId & " = vec3(0.75, 0.75, 0.78);\n"

    memo[nodeId] = "d_" & $nodeId
    return ("d_" & $nodeId, "c_" & $nodeId)

  if arena.root >= 0:
    discard emit(arena.root, "p")

  let source = """
#version 430
in vec2 v_uv;
out vec4 fragColor;
""" & GLSL_LIBRARY & """
vec4 mapScene(vec3 p) {
""" & body & """
  return vec4(d_""" & $arena.root & """, c_""" & $arena.root & """);
}
"""
  result = GLSLProgram(source: source, uniforms: uniformNames,
                       nodeCount: arena.nodes.len)
