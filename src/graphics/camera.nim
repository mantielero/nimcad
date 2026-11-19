import math
import ../core/sdf_ast

type
  Camera* = object
    yaw*, pitch*, distance*: float
    pivot*: Vec3
    ortho*: bool
    orthoScale*: float

proc initCamera*: Camera =
  Camera(yaw: 0.785398, pitch: 0.45, distance: 90.0,
         pivot: vec3(0, 0, 0), ortho: false, orthoScale: 55.0)

proc orbit*(camera: var Camera, dx, dy: float) =
  camera.yaw += dx
  camera.pitch = clamp(camera.pitch + dy, -1.55, 1.55)

proc pan*(camera: var Camera, dx, dy: float) =
  camera.pivot.x -= dx * camera.distance * 0.002
  camera.pivot.y += dy * camera.distance * 0.002

proc zoom*(camera: var Camera, amount: float) =
  camera.distance = clamp(camera.distance * exp(amount), 0.5, 1000.0)

proc setView*(camera: var Camera, yaw, pitch: float) =
  camera.yaw = yaw
  camera.pitch = pitch
