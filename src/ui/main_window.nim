import std/[times]
import ../core/[sdf_ast, params, script_engine]
import ../compiler/glsl_gen
import ../graphics/[camera, renderer, mesher]

type
  ConsoleLine* = object
    text*: string
    isError*: bool

  MainWindow* = object
    engine*: ScriptEngine
    camera*: Camera
    renderer*: Renderer
    scriptText*: string
    console*: seq[ConsoleLine]
    activeFile*: string

proc initMainWindow*(file = "examples/01_hola_mundo.nims"): MainWindow =
  var engine = initScriptEngine(file)
  MainWindow(engine: engine, camera: initCamera(), renderer: initRenderer(),
             scriptText: "", console: @[], activeFile: file)

proc compileActiveScript*(window: var MainWindow): ScriptResult =
  var engine = window.engine
  result = evaluateFile(engine, window.activeFile)
  window.engine = engine
  window.console.setLen(0)
  for message in result.output:
    window.console.add(ConsoleLine(text: message, isError: false))
  for error in result.errors:
    window.console.add(ConsoleLine(text:
      "Line " & $error.line & ", column " & $error.column & ": " & error.message,
      isError: true))
  if result.root >= 0:
    window.renderer.shaderSource = buildFragmentSource(result.arena)
    window.renderer.metrics.nodeCount = result.arena.nodes.len
    window.renderer.metrics.scriptMs = result.elapsedMs

proc runMainWindow* =
  var window = initMainWindow()
  let result = window.compileActiveScript()
  echo "NimCAD-SDF 0.1.0"
  echo "Loaded: " & window.activeFile
  echo "SDF nodes: " & $result.arena.nodes.len
  echo "GLSL source ready: " & $window.renderer.shaderSource.len & " bytes"
  echo "Merenda UI host: enable graphical backend with -d:nimcadMerenda"
