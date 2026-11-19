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

  ValueKind = enum valueNumber, valueNode, valueString, valueTuple
  ScriptValue = object
    case kind: ValueKind
    of valueNumber:
      number: float
    of valueNode:
      node: int
    of valueString:
      text: string
    of valueTuple:
      items: seq[ScriptValue]
  TokenKind = enum tokenIdentifier, tokenNumber, tokenString, tokenSymbol, tokenEnd
  Token = object
    kind: TokenKind
    text: string
  Argument = object
    name: string
    value: ScriptValue
  Symbol = object
    name: string
    value: ScriptValue
  Procedure = object
    name: string
    body: seq[string]
  LogicalLine = object
    text: string
    indent, sourceLine: int
  EvalContext = object
    arena: SDFArena
    symbols: seq[Symbol]
    procedures: seq[Procedure]
    params: seq[Param]
    output: seq[string]
    errors: seq[ScriptError]
    root: int
  Parser = object
    tokens: seq[Token]
    pos: int

proc initScriptEngine*(file = "examples/01_hola_mundo.nims"): ScriptEngine =
  ScriptEngine(activeFile: file, lastStamp: Time(), params: @[])

proc numberValue(value: float): ScriptValue =
  ScriptValue(kind: valueNumber, number: value)

proc nodeValue(value: int): ScriptValue =
  ScriptValue(kind: valueNode, node: value)

proc tokenize(code: string): seq[Token] =
  var i = 0
  while i < code.len:
    let c = code[i]
    if c.isSpaceAscii:
      inc i
    elif c.isAlphaAscii or c == '_':
      let start = i
      inc i
      while i < code.len and (code[i].isAlphaNumeric or code[i] == '_'):
        inc i
      result.add(Token(kind: tokenIdentifier, text: code[start ..< i]))
    elif c.isDigit or (c == '.' and i + 1 < code.len and code[i + 1].isDigit):
      let start = i
      inc i
      while i < code.len and
          (code[i].isDigit or code[i] == '.' or code[i] == 'e' or
           code[i] == 'E' or
           ((code[i] == '+' or code[i] == '-') and i > start and
            code[i - 1] in {'e', 'E'})):
        inc i
      result.add(Token(kind: tokenNumber, text: code[start ..< i]))
    elif c == '"':
      inc i
      var value = ""
      while i < code.len and code[i] != '"':
        if code[i] == '\\' and i + 1 < code.len:
          inc i
        value.add(code[i])
        inc i
      if i == code.len:
        raise newException(ValueError, "unterminated string literal")
      inc i
      result.add(Token(kind: tokenString, text: value))
    else:
      result.add(Token(kind: tokenSymbol, text: $c))
      inc i
  result.add(Token(kind: tokenEnd, text: ""))

proc current(parser: Parser): Token =
  parser.tokens[parser.pos]

proc accept(parser: var Parser, text: string): bool =
  if parser.current.text == text:
    inc parser.pos
    return true

proc expect(parser: var Parser, text: string) =
  if not parser.accept(text):
    raise newException(ValueError, "expected '" & text & "'")

proc lookup(context: EvalContext, name: string): ScriptValue =
  for index in countdown(context.symbols.high, 0):
    if context.symbols[index].name == name:
      return context.symbols[index].value
  raise newException(ValueError, "unknown identifier '" & name & "'")

proc assign(context: var EvalContext, name: string, value: ScriptValue) =
  for index in countdown(context.symbols.high, 0):
    if context.symbols[index].name == name:
      context.symbols[index].value = value
      return
  context.symbols.add(Symbol(name: name, value: value))

proc asNumber(value: ScriptValue): float =
  if value.kind != valueNumber:
    raise newException(ValueError, "expected a numeric expression")
  value.number

proc asNode(value: ScriptValue): int =
  if value.kind != valueNode:
    raise newException(ValueError, "expected an SDF shape")
  value.node

proc argValue(args: openArray[Argument], name: string,
              position: int): ScriptValue =
  for arg in args:
    if arg.name == name:
      return arg.value
  var index = 0
  for arg in args:
    if arg.name.len == 0:
      if index == position:
        return arg.value
      inc index
  numberValue(0)

proc argNumber(args: openArray[Argument], name: string, position: int,
               fallback: float): float =
  for arg in args:
    if arg.name == name:
      return arg.value.asNumber()
  var index = 0
  for arg in args:
    if arg.name.len == 0:
      if index == position:
        return arg.value.asNumber()
      inc index
  fallback

proc asVec3(value: ScriptValue): Vec3 =
  if value.kind != valueTuple or value.items.len != 3:
    raise newException(ValueError, "expected a three-component tuple")
  vec3(value.items[0].asNumber(), value.items[1].asNumber(),
         value.items[2].asNumber())

proc parseExpression(parser: var Parser,
                     context: var EvalContext): ScriptValue

proc invokeProcedure(context: var EvalContext, name: string): ScriptValue

proc parseArguments(parser: var Parser,
                    context: var EvalContext): seq[Argument] =
  parser.expect("(")
  if parser.accept(")"):
    return
  while true:
    var name = ""
    if parser.current.kind == tokenIdentifier and
        parser.tokens[parser.pos + 1].text == "=":
      name = parser.current.text
      inc parser.pos
      parser.expect("=")
    result.add(Argument(name: name,
      value: parser.parseExpression(context)))
    if parser.accept(")"):
      break
    parser.expect(",")

proc applyCall(name: string, args: openArray[Argument],
               receiver: ScriptValue, hasReceiver: bool,
               context: var EvalContext): ScriptValue =
  if hasReceiver:
    let child = receiver.asNode()
    case name
    of "move", "translate":
      return nodeValue(context.arena.move(child,
        argNumber(args, "x", 0, 0), argNumber(args, "y", 1, 0),
        argNumber(args, "z", 2, 0)))
    of "round":
      return nodeValue(context.arena.roundNode(child,
        argNumber(args, "r", 0, 0)))
    of "onion":
      return nodeValue(context.arena.onion(child,
        argNumber(args, "thickness", 0, 1)))
    of "color":
      return nodeValue(context.arena.withColor(child,
        argNumber(args, "r", 0, 0.75), argNumber(args, "g", 1, 0.75),
        argNumber(args, "b", 2, 0.78)))
    of "repeatPolar":
      return nodeValue(context.arena.repeatPolar(child,
        int(argNumber(args, "count", 0, 1))))
    of "twist":
      return nodeValue(context.arena.twist(child,
        argNumber(args, "k", 0, 0)))
    of "bend":
      return nodeValue(context.arena.bend(child,
        argNumber(args, "k", 0, 0)))
    of "scale":
      return nodeValue(context.arena.scaleNode(child,
        argNumber(args, "s", 0, 1)))
    else:
      raise newException(ValueError, "unsupported shape method '" & name & "'")

  for procedure in context.procedures:
    if procedure.name == name:
      if args.len != 0:
        raise newException(ValueError,
          "procedure '" & name & "' does not accept arguments")
      return context.invokeProcedure(name)

  case name
  of "sphere":
    return nodeValue(context.arena.sphere(argNumber(args, "r", 0, 10)))
  of "box":
    let x = argNumber(args, "x", 0, 10)
    return nodeValue(context.arena.box(x,
      argNumber(args, "y", 1, x), argNumber(args, "z", 2, x)))
  of "roundBox":
    return nodeValue(context.arena.roundBox(
      argNumber(args, "x", 0, 10), argNumber(args, "y", 1, 10),
      argNumber(args, "z", 2, 10), argNumber(args, "r", 3, 1)))
  of "cylinder":
    return nodeValue(context.arena.cylinder(argNumber(args, "r", 0, 10),
      argNumber(args, "h", 1, 20)))
  of "torus":
    return nodeValue(context.arena.torus(argNumber(args, "majorR", 0, 10),
      argNumber(args, "minorR", 1, 2)))
  of "union", "smoothUnion", "smoothSub", "smoothIntersection":
    let a = argValue(args, "a", 0).asNode()
    let b = argValue(args, "b", 1).asNode()
    let k = argNumber(args, "k", 2, 1)
    let kind = case name
      of "union": nkUnion
      of "smoothUnion": nkSmoothUnion
      of "smoothSub": nkSmoothSubtraction
      else: nkSmoothIntersection
    return nodeValue(context.arena.booleanNode(kind, a, b, k))
  of "displace":
    let child = argValue(args, "shape", 0).asNode()
    let expression = argValue(args, "expression", 1)
    if expression.kind != valueString:
      raise newException(ValueError, "displacement must be a string")
    return nodeValue(context.arena.displace(child, expression.text))
  of "repeatFinite":
    let child = argValue(args, "shape", 0).asNode()
    let spacing = argValue(args, "spacing", 1).asVec3()
    let count = argValue(args, "count", 2).asVec3()
    return nodeValue(context.arena.repeatFinite(child,
      spacing.x, spacing.y, spacing.z, count.x, count.y, count.z))
  of "render":
    let root = argValue(args, "shape", 0).asNode()
    context.root = root
    return nodeValue(root)
  of "param", "paramInt":
    let labelValue = argValue(args, "name", 0)
    if labelValue.kind != valueString:
      raise newException(ValueError, "parameter name must be a string")
    let value = argNumber(args, "defaultValue", 1, 1)
    let minValue = argNumber(args, "min", 2, 0)
    let maxValue = argNumber(args, "max", 3, value)
    if name == "paramInt":
      return numberValue(float(paramInt(context.params, labelValue.text,
        int(value), int(minValue), int(maxValue))))
    let paramValue = paramFloat(context.params, labelValue.text, value,
                                minValue, maxValue)
    return numberValue(paramValue)
  of "echo":
    let value = argValue(args, "", 0)
    case value.kind
    of valueString: context.output.add(value.text)
    of valueNumber: context.output.add($value.number)
    else: raise newException(ValueError, "echo supports strings and numbers")
    return numberValue(0)
  else:
    raise newException(ValueError, "unsupported function '" & name & "'")

proc parsePrimary(parser: var Parser,
                  context: var EvalContext): ScriptValue =
  let token = parser.current
  case token.kind
  of tokenNumber:
    inc parser.pos
    try:
      return numberValue(parseFloat(token.text))
    except ValueError:
      raise newException(ValueError, "invalid number '" & token.text & "'")
  of tokenString:
    inc parser.pos
    return ScriptValue(kind: valueString, text: token.text)
  of tokenIdentifier:
    inc parser.pos
    if parser.current.text == "(":
      return applyCall(token.text, parser.parseArguments(context),
                       numberValue(0), false, context)
    return context.lookup(token.text)
  of tokenSymbol:
    if parser.accept("("):
      let first = parser.parseExpression(context)
      if parser.accept(","):
        var items = @[first]
        while true:
          items.add(parser.parseExpression(context))
          if parser.accept(")"):
            break
          parser.expect(",")
        return ScriptValue(kind: valueTuple, items: items)
      parser.expect(")")
      return first
    raise newException(ValueError, "unexpected token '" & token.text & "'")
  of tokenEnd:
    raise newException(ValueError, "expected an expression")

proc parsePostfix(parser: var Parser,
                  context: var EvalContext): ScriptValue =
  result = parser.parsePrimary(context)
  while parser.accept("."):
    if parser.current.kind != tokenIdentifier:
      raise newException(ValueError, "expected a shape method name")
    let name = parser.current.text
    inc parser.pos
    result = applyCall(name, parser.parseArguments(context), result, true,
                       context)

proc parseUnary(parser: var Parser,
                context: var EvalContext): ScriptValue =
  if parser.accept("-"):
    return numberValue(-parser.parseUnary(context).asNumber())
  if parser.accept("+"):
    return parser.parseUnary(context)
  parser.parsePostfix(context)

proc combine(context: var EvalContext, operator: string,
             left, right: ScriptValue): ScriptValue =
  if left.kind == valueNumber and right.kind == valueNumber:
    case operator
    of "+": return numberValue(left.number + right.number)
    of "-": return numberValue(left.number - right.number)
    of "*": return numberValue(left.number * right.number)
    of "/":
      if right.number == 0:
        raise newException(ValueError, "division by zero")
      return numberValue(left.number / right.number)
    else: discard
  let a = left.asNode()
  let b = right.asNode()
  case operator
  of "+": return nodeValue(context.arena.opUnion(a, b))
  of "-": return nodeValue(context.arena.opSubtraction(a, b))
  of "*": return nodeValue(context.arena.opIntersection(a, b))
  else: raise newException(ValueError, "unsupported operator '" & operator & "'")

proc parseProduct(parser: var Parser,
                  context: var EvalContext): ScriptValue =
  result = parser.parseUnary(context)
  while parser.current.text == "*" or parser.current.text == "/":
    let operator = parser.current.text
    inc parser.pos
    result = combine(context, operator, result, parser.parseUnary(context))

proc parseExpression(parser: var Parser,
                     context: var EvalContext): ScriptValue =
  result = parser.parseProduct(context)
  while parser.current.text == "+" or parser.current.text == "-":
    let operator = parser.current.text
    inc parser.pos
    result = combine(context, operator, result, parser.parseProduct(context))

proc parseScriptExpression(code: string,
                           context: var EvalContext): ScriptValue =
  var parser = Parser(tokens: tokenize(code), pos: 0)
  result = parser.parseExpression(context)
  if parser.current.kind != tokenEnd:
    raise newException(ValueError, "unexpected token '" &
      parser.current.text & "'")

proc uncomment(line: string): string =
  var inString = false
  var escaped = false
  for c in line:
    if c == '"' and not escaped:
      inString = not inString
    if c == '#' and not inString:
      break
    result.add(c)
    if c == '\\' and inString:
      escaped = not escaped
    else:
      escaped = false

proc logicalLines(code: string): seq[LogicalLine] =
  var accumulated = ""
  var parenDepth = 0
  var startLine = 0
  var indent = 0
  for lineNumber, rawLine in code.splitLines():
    let line = uncomment(rawLine)
    if line.strip().len == 0:
      continue
    var leading = 0
    while leading < rawLine.len and rawLine[leading] in {' ', '\t'}:
      inc leading
    if accumulated.len == 0:
      startLine = lineNumber + 1
      indent = leading
    else:
      accumulated.add(" ")
    accumulated.add(line.strip())
    for c in line:
      if c == '(':
        inc parenDepth
      elif c == ')':
        dec parenDepth
    if parenDepth <= 0:
      result.add(LogicalLine(text: accumulated, indent: indent,
                             sourceLine: startLine))
      accumulated = ""
      parenDepth = 0
  if accumulated.len > 0:
    result.add(LogicalLine(text: accumulated, indent: indent,
                           sourceLine: startLine))

proc parseScriptExpression(code: string,
                           context: var EvalContext): ScriptValue =
  var parser = Parser(tokens: tokenize(code), pos: 0)
  result = parser.parseExpression(context)
  if parser.current.kind != tokenEnd:
    raise newException(ValueError, "unexpected token '" &
      parser.current.text & "'")

proc invokeProcedure(context: var EvalContext, name: string): ScriptValue =
  for procedure in context.procedures:
    if procedure.name != name:
      continue
    let savedSymbols = context.symbols
    context.symbols = @[]
    for symbol in savedSymbols:
      context.symbols.add(symbol)
    try:
      for sourceLine in procedure.body:
        let line = sourceLine.strip()
        if line.startsWith("let ") or line.startsWith("var "):
          let equals = line.find('=')
          if equals < 0:
            raise newException(ValueError, "expected '=' in declaration")
          let variableName = line[4 ..< equals].strip()
          let value = parseScriptExpression(line[equals + 1 .. ^1], context)
          context.symbols.add(Symbol(name: variableName, value: value))
        elif line.startsWith("return "):
          result = parseScriptExpression(line[7 .. ^1], context)
          return
        elif line.contains('='):
          let equals = line.find('=')
          context.assign(line[0 ..< equals].strip(),
            parseScriptExpression(line[equals + 1 .. ^1], context))
        else:
          discard parseScriptExpression(line, context)
      raise newException(ValueError,
        "procedure '" & name & "' did not return a value")
    finally:
      context.symbols = savedSymbols
  raise newException(ValueError, "unknown procedure '" & name & "'")

proc evalLineScript*(code: string): ScriptResult =
  var context = EvalContext(arena: initSDFArena(), params: @[], output: @[],
                            errors: @[], root: -1)
  let started = epochTime()
  let lines = logicalLines(code)
  var lineIndex = 0
  while lineIndex < lines.len:
    let logical = lines[lineIndex]
    let line = logical.text.strip()
    if line.len == 0 or line.startsWith("import "):
      inc lineIndex
      continue
    if logical.indent == 0 and line.startsWith("proc "):
      let openParen = line.find('(')
      if openParen < 0:
        context.errors.add(ScriptError(line: logical.sourceLine, column: 1,
          message: "expected a procedure parameter list"))
        inc lineIndex
        continue
      let procedureName = line[5 ..< openParen].strip()
      if procedureName.len == 0 or not line.endsWith("="):
        context.errors.add(ScriptError(line: logical.sourceLine, column: 1,
          message: "expected a procedure declaration ending with '='"))
        inc lineIndex
        continue
      var procedure = Procedure(name: procedureName, body: @[])
      inc lineIndex
      while lineIndex < lines.len and lines[lineIndex].indent > logical.indent:
        procedure.body.add(lines[lineIndex].text)
        inc lineIndex
      if procedure.body.len == 0:
        context.errors.add(ScriptError(line: logical.sourceLine, column: 1,
          message: "procedure body must not be empty"))
      else:
        context.procedures.add(procedure)
      continue
    try:
      if line.startsWith("let ") or line.startsWith("var "):
        let equals = line.find('=')
        if equals < 0:
          raise newException(ValueError, "expected '=' in declaration")
        let name = line[4 ..< equals].strip()
        if name.len == 0:
          raise newException(ValueError, "expected a variable name")
        context.assign(name, parseScriptExpression(line[equals + 1 .. ^1],
                                                    context))
      elif line.startsWith("render(") or line.startsWith("echo("):
        discard parseScriptExpression(line, context)
      elif line.startsWith("return "):
        raise newException(ValueError,
          "return is only supported inside a procedure")
      elif line.contains('='):
        let equals = line.find('=')
        context.assign(line[0 ..< equals].strip(),
          parseScriptExpression(line[equals + 1 .. ^1], context))
      else:
        discard parseScriptExpression(line, context)
    except ValueError as error:
      context.errors.add(ScriptError(line: logical.sourceLine, column: 1,
                                     message: error.msg))
    inc lineIndex

  context.arena.root = context.root
  result = ScriptResult(arena: context.arena, params: context.params,
    output: context.output, errors: context.errors,
    elapsedMs: (epochTime() - started) * 1000, root: context.root)

proc evaluateFile*(engine: var ScriptEngine, path: string): ScriptResult =
  engine.activeFile = path
  try:
    result = evalLineScript(readFile(path))
    engine.params = result.params
  except IOError as error:
    result.errors.add(ScriptError(line: 1, column: 1, message: error.msg))

proc fileChanged*(engine: var ScriptEngine, path: string): bool =
  if not fileExists(path):
    return false
  let stamp = getLastModificationTime(path)
  stamp != engine.lastStamp
