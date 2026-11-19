import nimcad

let escala = param("Escala", 12.0, min = 6.0, max = 25.0)
let grosor = param("Grosor", 1.2, min = 0.2, max = 4.0)

let giroide = displace(
  sphere(r = 35.0),
  "sin(p.x / 12.0) * cos(p.y / 12.0) + sin(p.z / 12.0)"
).onion(grosor).twist(k = 0.015)

render(giroide.color(0.78, 0.25, 0.65))
