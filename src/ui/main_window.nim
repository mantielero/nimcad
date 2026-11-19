import std/os
import ../core/[sdf_ast, script_engine]
import ../graphics/[camera, renderer, viewport]

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

proc runMainWindow*(filePath = "examples/01_hola_mundo.nims"): int =
  var window = initMainWindow(filePath)
  let scriptResult = window.compileActiveScript()
  for line in window.console:
    if line.isError:
      stderr.writeLine(filePath & ":" & $line.text)
      return 1
    echo line.text
  if scriptResult.root < 0:
    stderr.writeLine("No render(...) root found in " & filePath)
    return 1

  echo "NimCAD-SDF 0.1.0"
  echo "Loaded: " & window.activeFile
  echo "SDF nodes: " & $scriptResult.arena.nodes.len
  echo "GLSL source ready: " & $window.renderer.shaderSource.len & " bytes"
  echo "Opening 3D viewport (middle-drag: orbit, Shift+middle-drag: pan, wheel: zoom, Esc: close)"

  let bounds = aabbFor(scriptResult.arena.nodes[scriptResult.root],
                       scriptResult.arena.nodes)
  try:
    runViewport(window.renderer.shaderSource, "NimCAD-SDF - " &
      lastPathPart(filePath), bounds)
  except IOError as error:
    stderr.writeLine(error.msg)
    return 1
