import core/[sdf_ast, params, script_engine]
import compiler/glsl_gen
import graphics/[camera, renderer, mesher]
import ui/main_window

when isMainModule:
  runMainWindow()
