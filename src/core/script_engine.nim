import std/[times, strutils, os]
import sdf_ast
import params

type
  ScriptError* = object
    line*, column*: int
    message*: string
  ScriptResult* = object
    arena*: SDFArena
    params*: seq[Param]
    output*: seq[string]
    errors*: seq[ScriptError]
    elapsedMs*: float
    root*: int

  ScriptEngine* = object
    activeFile*: string
    lastStamp*: Time
    params*: seq[Param]

proc initScriptEngine*(file = "examples/01_hola_mundo.nims"): ScriptEngine =
  ScriptEngine(activeFile: file, lastStamp: Time(), params: @[])

proc floatFromText(text: string, fallback: float): float =
  let cleaned = text.strip(chars = {' ', ',', ')', ';'})
  if cleaned.len > 0:
    try: return parseFloat(cleaned)
    except ValueError: discard
  fallback

proc evalLineScript*(code: string): ScriptResult =
  var arena = initSDFArena()
  var params: seq[Param] = @[]
  var output: seq[string] = @[]
  var errors: seq[ScriptError] = @[]
  var ids: seq[int] = @[]
  var root = -1
  let started = epochTime()

  for line in code.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("import"):
      continue
    if trimmed.startsWith("echo(") or trimmed.startsWith("echo "):
      output.add(trimmed.substr(trimmed.find("(") + 1).strip(chars = {'"', ')'}))
    elif trimmed.startsWith("let ") or trimmed.startsWith("var "):
      if "sphere(" in trimmed:
        let r = floatFromText(trimmed.substr(trimmed.find("sphere(") + 7), 10.0)
        ids.add(arena.sphere(r))
      elif "box(" in trimmed:
        let rest = trimmed.substr(trimmed.find("box(") + 4)
        let parts = rest.split(',')
        let x = if parts.len > 0: floatFromText(parts[0], 10.0) else: 10.0
        let y = if parts.len > 1: floatFromText(parts[1], 10.0) else: x
        let z = if parts.len > 2: floatFromText(parts[2], 10.0) else: x
        ids.add(arena.box(x, y, z))
      elif "cylinder(" in trimmed:
        let rest = trimmed.substr(trimmed.find("cylinder(") + 9)
        var r = 10.0
        var h = 20.0
        for part in rest.split(','):
          if part.strip().startsWith("r"):
            r = floatFromText(part.substr(part.find('=') + 1), r)
          elif part.strip().startsWith("h"):
            h = floatFromText(part.substr(part.find('=') + 1), h)
        ids.add(arena.cylinder(r, h))
      elif "param(" in trimmed:
        let eq = trimmed.find('=')
        if eq >= 0:
          let name = trimmed[4..<eq].strip()
          let rest = trimmed.substr(trimmed.find("param(") + 6)
          let defaultText = rest.split(',')[0]
          let value = floatFromText(defaultText, 1.0)
          let labelStart = rest.find('"')
          let labelEnd = rest.find('"', labelStart + 1)
          let label = if labelStart >= 0 and labelEnd > labelStart:
                        rest[labelStart + 1..<labelEnd] else: name
          let minPos = rest.find("min")
          var minV = 0.0
          var maxV = value
          if minPos >= 0:
            minV = floatFromText(rest.substr(minPos + 4).split(',')[0], 0.0)
          let maxPos = rest.find("max")
          if maxPos >= 0:
            maxV = floatFromText(rest.substr(maxPos + 4).split(',')[0], value)
          discard paramFloat(params, label, value, minV, maxV)
    elif trimmed.startsWith("render(") or trimmed.startsWith("result "):
      if ids.len > 0:
        root = ids[^1]
    elif " smoothUnion(" in trimmed:
      if ids.len >= 2:
        let k = if "k =" in trimmed: floatFromText(trimmed.substr(trimmed.find("k =") + 3), 1.0) else: 1.0
        let id = arena.booleanNode(nkSmoothUnion, ids[^2], ids[^1], k)
        ids.add(id)
    elif trimmed.startsWith("proc ") or trimmed.endsWith(" ="):
      continue
    elif trimmed.startsWith("return "):
      let returnName = trimmed.substr(7).strip(chars = {'(', ')'})
      if ids.len > 0:
        root = ids[^1]

  if root < 0 and ids.len > 0:
    root = ids[^1]
  arena.root = root
  result = ScriptResult(arena: arena, params: params, output: output,
                        errors: errors, elapsedMs: (epochTime() - started) * 1000,
                        root: root)

proc evaluateFile*(engine: var ScriptEngine, path: string): ScriptResult =
  engine.activeFile = path
  try:
    let code = readFile(path)
    result = evalLineScript(code)
  except IOError as e:
    result.errors.add(ScriptError(line: 1, column: 1, message: e.msg))

proc fileChanged*(engine: ScriptEngine, path: string): bool =
  if not fileExists(path):
    return false
  let stamp = getLastModificationTime(path)
  stamp != engine.lastStamp
