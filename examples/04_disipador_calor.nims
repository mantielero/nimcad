import nimcad

let pas = param("Paso", 4.0, min = 2.0, max = 8.0)
let alto = param("Altura Aletas", 18.0, min = 8.0, max = 30.0)

let base = box(50.0, 50.0, 3.0)
let aleta = box(1.2, pas * 0.8, alto).move(z = alto * 0.5)
let disipador = base + repeatFinite(aleta, spacing = (pas, pas, 0.0), count = (12, 12, 0))

render(disipador.color(0.45, 0.58, 0.68))
