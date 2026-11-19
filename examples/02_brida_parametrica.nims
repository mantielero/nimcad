import nimcad

let radioBase = param("Radio Base", 25.0, min = 10.0, max = 50.0)
let altura = param("Altura Torre", 40.0, min = 15.0, max = 80.0)
let suavizado = param("Filete Union", 3.5, min = 0.0, max = 10.0)
let numAgujeros = paramInt("Taladros", 6, min = 3, max = 12)

proc crearBrida(): SDFNode =
  let base = cylinder(r = radioBase, h = 6.0).round(0.8)
  let cuerpo = cylinder(r = radioBase * 0.55, h = altura).move(z = altura * 0.5)
  var pieza = smoothUnion(base, cuerpo, k = suavizado)
  let huecoCentral = cylinder(r = radioBase * 0.35, h = altura + 20.0)
  pieza = pieza - huecoCentral
  let taladro = cylinder(r = 2.5, h = 15.0).move(x = radioBase * 0.78)
  let coronaTaladros = taladro.repeatPolar(count = numAgujeros)
  return (pieza - coronaTaladros).color(0.2, 0.65, 0.9)

render(crearBrida())
