type
  ParamKind* = enum pkFloat, pkInt, pkBool, pkColor
  Param* = object
    name*, label*: string
    kind*: ParamKind
    floatValue*, min*, max*: float
    intValue*, intMin*, intMax*: int
    boolValue*: bool
    color*: tuple[r, g, b, a: float]

proc clearParams*(params: var seq[Param]) =
  params.setLen(0)

proc paramFloat*(params: var seq[Param], name: string, value, min, max: float): float =
  for p in mitems(params):
    if p.name == name:
      p.floatValue = value
      return p.floatValue
  params.add Param(name: name, label: name, kind: pkFloat,
                   floatValue: value, min: min, max: max)
  value

proc paramInt*(params: var seq[Param], name: string, value, min, max: int): int =
  for p in mitems(params):
    if p.name == name:
      p.intValue = value
      return p.intValue
  params.add Param(name: name, label: name, kind: pkInt,
                   intValue: value, intMin: min, intMax: max)
  value

proc paramBool*(params: var seq[Param], name: string, value: bool): bool =
  params.add Param(name: name, label: name, kind: pkBool, boolValue: value)
  value
