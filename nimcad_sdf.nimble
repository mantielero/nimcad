packageName = "nimcad_sdf"
version = "0.1.0"
author = "NimCAD contributors"
description = "Parametric GPU-accelerated SDF CAD for Nim"
license = "MIT"
srcDir = "src"
bin = @["nimcad"]

requires "nim >= 2.0.0"
requires "vmath >= 1.2.0"
requires "opengl >= 1.2.0"
requires "merenda >= 0.1.0"
requires "staticglfw >= 0.1.0"

task test, "Run the NimCAD test suite":
  exec "nim c -r --mm:orc --threads:on --path:src tests/test_sdf.nim"
