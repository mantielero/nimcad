import math, sets

type
  Vec3* = tuple[x, y, z: float]
  Axis* = enum axX, axY, axZ
  AABB* = object
    lo*, hi*: Vec3
  SDFNodeKind* = enum
    nkSphere, nkBox, nkRoundBox, nkTorus, nkCylinder, nkCapsule,
    nkCone, nkHexPrism, nkTriPrism, nkOctahedron, nkEllipsoid,
    nkUnion, nkSubtraction, nkIntersection,
    nkSmoothUnion, nkSmoothSubtraction, nkSmoothIntersection,
    nkRound, nkOnion, nkExtrude2D, nkRevolve2D,
    nkTranslate, nkRotate, nkScale, nkMirror,
    nkRepeatFinite, nkRepeatPolar, nkTwist, nkBend, nkDisplace,
    nkColor
  SDFNode* = object
    kind*: SDFNodeKind
    id*: int
    a*, b*: int
    radius*, height*, majorRadius*, minorRadius*, thickness*: float
    size*, pointA*, pointB*, offset*: Vec3
    spacing*: Vec3
    count*: int
    countVec*: Vec3
    angle*, bend*, twist*, scale*: float
    axes*: set[Axis]
    material*: Vec3
    expression*: string

proc vec3*(x, y = 0.0, z = 0.0): Vec3 =
  (x: x, y: y, z: z)

proc `+`*(a, b: Vec3): Vec3 =
  (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

proc `-`*(a, b: Vec3): Vec3 =
  (x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)

proc `*`*(a: Vec3, s: float): Vec3 =
  (x: a.x * s, y: a.y * s, z: a.z * s)

proc invalidAABB*: AABB =
  AABB(lo: vec3(Inf, Inf, Inf), hi: vec3(-Inf, -Inf, -Inf))

proc aabbFor*(node: SDFNode, arena: openArray[SDFNode]): AABB =
  case node.kind
  of nkSphere:
    let r = node.radius
    AABB(lo: vec3(-r, -r, -r), hi: vec3(r, r, r))
  of nkBox, nkRoundBox:
    AABB(lo: node.size * -1.0, hi: node.size)
  of nkTorus:
    let r = node.majorRadius + node.minorRadius
    AABB(lo: vec3(-r, -node.minorRadius, -r),
         hi: vec3(r, node.minorRadius, r))
  of nkCylinder:
    let h = node.height * 0.5
    AABB(lo: vec3(-node.radius, -h, -node.radius),
         hi: vec3(node.radius, h, node.radius))
  of nkCapsule:
    let loX = min(node.pointA.x, node.pointB.x) - node.radius
    let hiX = max(node.pointA.x, node.pointB.x) + node.radius
    let loY = min(node.pointA.y, node.pointB.y) - node.radius
    let hiY = max(node.pointA.y, node.pointB.y) + node.radius
    let loZ = min(node.pointA.z, node.pointB.z) - node.radius
    let hiZ = max(node.pointA.z, node.pointB.z) + node.radius
    AABB(lo: vec3(loX, loY, loZ), hi: vec3(hiX, hiY, hiZ))
  of nkCone:
    let h = node.height * 0.5
    let r = node.radius
    AABB(lo: vec3(-r, -h, -r), hi: vec3(r, h, r))
  of nkHexPrism, nkTriPrism:
    AABB(lo: vec3(-node.radius, -node.height * 0.5, -node.radius),
         hi: vec3(node.radius, node.height * 0.5, node.radius))
  of nkOctahedron:
    AABB(lo: vec3(-node.radius, -node.radius, -node.radius),
         hi: vec3(node.radius, node.radius, node.radius))
  of nkEllipsoid:
    AABB(lo: node.size * -1.0, hi: node.size)
  of nkTranslate:
    let child = aabbFor(arena[node.a], arena)
    AABB(lo: child.lo + node.offset, hi: child.hi + node.offset)
  of nkScale:
    let child = aabbFor(arena[node.a], arena)
    AABB(lo: child.lo * node.scale, hi: child.hi * node.scale)
  of nkRepeatFinite:
    let child = aabbFor(arena[node.a], arena)
    let span = vec3(node.spacing.x * node.countVec.x,
                    node.spacing.y * node.countVec.y,
                    node.spacing.z * node.countVec.z)
    AABB(lo: child.lo - span, hi: child.hi + span)
  of nkUnion, nkSubtraction, nkIntersection,
     nkSmoothUnion, nkSmoothSubtraction, nkSmoothIntersection:
    let a = aabbFor(arena[node.a], arena)
    let b = aabbFor(arena[node.b], arena)
    if node.kind == nkSubtraction or node.kind == nkSmoothSubtraction:
      a
    else:
      AABB(lo: vec3(min(a.lo.x, b.lo.x), min(a.lo.y, b.lo.y), min(a.lo.z, b.lo.z)),
           hi: vec3(max(a.hi.x, b.hi.x), max(a.hi.y, b.hi.y), max(a.hi.z, b.hi.z)))
  else:
    if node.a >= 0 and node.a < arena.len:
      aabbFor(arena[node.a], arena)
    else:
      invalidAABB()

type SDFArena* = object
  nodes*: seq[SDFNode]
  root*: int

proc initSDFArena*: SDFArena =
  SDFArena(nodes: @[], root: -1)

proc addNode*(arena: var SDFArena, node: SDFNode): int =
  var copy = node
  copy.id = arena.nodes.len
  arena.nodes.add(copy)
  result = copy.id

proc sphere*(arena: var SDFArena, r: float): int =
  arena.addNode(SDFNode(kind: nkSphere, a: -1, b: -1, radius: r,
                        material: vec3(0.75, 0.75, 0.78)))
proc box*(arena: var SDFArena, x, y, z: float): int =
  arena.addNode(SDFNode(kind: nkBox, a: -1, b: -1, size: vec3(x, y, z),
                        material: vec3(0.75, 0.75, 0.78)))
proc roundBox*(arena: var SDFArena, x, y, z, r: float): int =
  arena.addNode(SDFNode(kind: nkRoundBox, a: -1, b: -1, size: vec3(x, y, z),
                        radius: r, material: vec3(0.75, 0.75, 0.78)))
proc torus*(arena: var SDFArena, majorRadius, minorRadius: float): int =
  arena.addNode(SDFNode(kind: nkTorus, a: -1, b: -1,
                        majorRadius: majorRadius, minorRadius: minorRadius,
                        material: vec3(0.75, 0.75, 0.78)))
proc cylinder*(arena: var SDFArena, r, h: float): int =
  arena.addNode(SDFNode(kind: nkCylinder, a: -1, b: -1,
                        radius: r, height: h,
                        material: vec3(0.75, 0.75, 0.78)))
proc capsule*(arena: var SDFArena, ax, ay, az, bx, by, bz, r: float): int =
  arena.addNode(SDFNode(kind: nkCapsule, a: -1, b: -1,
                        pointA: vec3(ax, ay, az), pointB: vec3(bx, by, bz),
                        radius: r, material: vec3(0.75, 0.75, 0.78)))
proc ellipsoid*(arena: var SDFArena, x, y, z: float): int =
  arena.addNode(SDFNode(kind: nkEllipsoid, a: -1, b: -1, size: vec3(x, y, z),
                        material: vec3(0.75, 0.75, 0.78)))

proc booleanNode*(arena: var SDFArena, kind: SDFNodeKind, a, b: int,
                  k = 0.0): int =
  arena.addNode(SDFNode(kind: kind, a: a, b: b, thickness: k,
                        material: vec3(0.75, 0.75, 0.78)))
proc opUnion*(arena: var SDFArena, a, b: int): int =
  arena.booleanNode(nkUnion, a, b)
proc opSubtraction*(arena: var SDFArena, a, b: int): int =
  arena.booleanNode(nkSubtraction, a, b)
proc opIntersection*(arena: var SDFArena, a, b: int): int =
  arena.booleanNode(nkIntersection, a, b)

proc unaryNode*(arena: var SDFArena, kind: SDFNodeKind, a: int,
                value = 0.0): int =
  arena.addNode(SDFNode(kind: kind, a: a, b: -1, thickness: value,
                        radius: value, material: vec3(0.75, 0.75, 0.78)))
proc roundNode*(arena: var SDFArena, a: int, r: float): int =
  arena.unaryNode(nkRound, a, r)
proc onion*(arena: var SDFArena, a: int, thickness: float): int =
  arena.unaryNode(nkOnion, a, thickness)
proc move*(arena: var SDFArena, a: int, x, y, z: float): int =
  arena.addNode(SDFNode(kind: nkTranslate, a: a, b: -1, offset: vec3(x, y, z)))
proc translate*(arena: var SDFArena, a: int, x, y, z: float): int =
  arena.move(a, x, y, z)
proc rotate*(arena: var SDFArena, a: int, x, y, z: float): int =
  arena.addNode(SDFNode(kind: nkRotate, a: a, b: -1, offset: vec3(x, y, z)))
proc scaleNode*(arena: var SDFArena, a: int, s: float): int =
  arena.addNode(SDFNode(kind: nkScale, a: a, b: -1, scale: s))
proc mirror*(arena: var SDFArena, a: int, axes: set[Axis]): int =
  arena.addNode(SDFNode(kind: nkMirror, a: a, b: -1, axes: axes))
proc repeatFinite*(arena: var SDFArena, a: int, sx, sy, sz, cx, cy, cz: float): int =
  arena.addNode(SDFNode(kind: nkRepeatFinite, a: a, b: -1,
                        spacing: vec3(sx, sy, sz),
                        countVec: vec3(cx, cy, cz)))
proc repeatPolar*(arena: var SDFArena, a: int, count: int): int =
  arena.addNode(SDFNode(kind: nkRepeatPolar, a: a, b: -1, count: count))
proc twist*(arena: var SDFArena, a: int, k: float): int =
  arena.addNode(SDFNode(kind: nkTwist, a: a, b: -1, twist: k))
proc bend*(arena: var SDFArena, a: int, k: float): int =
  arena.addNode(SDFNode(kind: nkBend, a: a, b: -1, bend: k))
proc displace*(arena: var SDFArena, a: int, expression: string): int =
  arena.addNode(SDFNode(kind: nkDisplace, a: a, b: -1, expression: expression))
proc withColor*(arena: var SDFArena, a: int, r, g, b: float): int =
  arena.addNode(SDFNode(kind: nkColor, a: a, b: -1, material: vec3(r, g, b)))
