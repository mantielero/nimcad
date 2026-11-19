# nimcad
## NimCAD-SDF

NimCAD-SDF is a parametric signed-distance-field CAD application written in Nim.
It builds a host-side SDF DAG, generates GLSL 430 raymarching shaders, exposes
reactive model parameters, and exports sampled geometry as binary STL.

### Build

```sh
nimble build
nimble run nimcad
```

The default entry point executes the bundled Hello World script and prints the
generated GPU shader size. The graphical Merenda/OpenGL backend is activated
through the Merenda package and `-d:nimcadMerenda` on platforms with a supported
window system.

### Example scripts

- `examples/01_hola_mundo.nims`
- `examples/02_brida_parametrica.nims`
- `examples/03_giroide_organico.nims`
- `examples/04_disipador_calor.nims`
