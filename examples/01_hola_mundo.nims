import nimcad

let esfera = sphere(r = 18.0)
let caja = box(24.0, 24.0, 24.0).move(x = 12.0)

render(smoothUnion(esfera, caja, k = 4.0).color(0.2, 0.65, 0.9))
echo("Hola desde NimCAD-SDF")
