import std/[streams, math]
import ../core/sdf_ast

type
  Triangle* = object
    a*, b*, c*: Vec3
  MeshStats* = object
    triangles*: int
    elapsedMs*: float

proc evaluateHostSDF*(arena: SDFArena, p: Vec3): float =
  proc visit(id: int): float =
    if id < 0 or id >= arena.nodes.len:
      return 1000.0
    let n = arena.nodes[id]
    case n.kind
    of nkSphere:
      sqrt(p.x * p.x + p.y * p.y + p.z * p.z) - n.radius
    of nkBox:
      let qx = abs(p.x) - n.size.x
      let qy = abs(p.y) - n.size.y
      let qz = abs(p.z) - n.size.z
      let outside = sqrt(max(qx, 0.0)^2 + max(qy, 0.0)^2 + max(qz, 0.0)^2)
      outside + min(max(qx, max(qy, qz)), 0.0)
    of nkCylinder:
      let dxy = sqrt(p.x * p.x + p.z * p.z) - n.radius
      let dz = abs(p.y) - n.height * 0.5
      min(max(dxy, dz), 0.0) + sqrt(max(dxy, 0.0)^2 + max(dz, 0.0)^2)
    of nkUnion:
      min(visit(n.a), visit(n.b))
    of nkSubtraction:
      max(visit(n.a), -visit(n.b))
    of nkIntersection:
      max(visit(n.a), visit(n.b))
    else:
      if n.a >= 0: visit(n.a) else: 1000.0
  visit(arena.root)

proc exportBinarySTL*(arena: SDFArena, path: string,
                      bounds: AABB = AABB(lo: vec3(-50, -50, -50),
                                         hi: vec3(50, 50, 50)),
                      voxel: float = 1.0): MeshStats =
  var stream = newFileStream(path, fmWrite)
  if stream.isNil:
    return MeshStats(triangles: 0)
  defer: stream.close()
  for i in 0..<80:
    stream.write(uint8(0))
  var triangleCount = uint32(0)
  var count0 = triangleCount
  stream.writeData(addr count0, sizeof(count0))
  var y = bounds.lo.y
  while y <= bounds.hi.y:
    var x = bounds.lo.x
    while x <= bounds.hi.x:
      var z = bounds.lo.z
      while z <= bounds.hi.z:
        let p = vec3(x, y, z)
        if evaluateHostSDF(arena, p) <= 0:
          let corners = [
            vec3(x, y, z), vec3(x + voxel, y, z),
            vec3(x, y + voxel, z), vec3(x + voxel, y + voxel, z)
          ]
          for tri in 0..<2:
            let aa = corners[if tri == 0: 0 else: 1]
            let bb = corners[if tri == 0: 1 else: 3]
            let cc = corners[if tri == 0: 2 else: 2]
            let nx = float32(0)
            let ny = float32(0)
            let nz = float32(1)
            for value in [nx, ny, nz,
                          float32(aa.x), float32(aa.y), float32(aa.z),
                          float32(bb.x), float32(bb.y), float32(bb.z),
                          float32(cc.x), float32(cc.y), float32(cc.z)]:
              var littleValue = value
              stream.writeData(addr littleValue, sizeof(littleValue))
              var attribute = uint16(0)
              stream.writeData(addr attribute, sizeof(attribute))
            triangleCount += 1
        z += voxel
      x += voxel
    y += voxel
  stream.setPosition(80)
  stream.writeData(addr triangleCount, sizeof(triangleCount))
  result = MeshStats(triangles: int(triangleCount))
