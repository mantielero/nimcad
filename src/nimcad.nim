import std/os
import ui/main_window

when isMainModule:
  if paramCount() > 1:
    stderr.writeLine("Usage: nimcad [file.nims]")
    quit(2)
  let filePath = if paramCount() == 1: paramStr(1)
                 else: "examples/01_hola_mundo.nims"
  quit(runMainWindow(filePath))
