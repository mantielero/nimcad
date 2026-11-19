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

On Linux, the bundled GLFW backend also needs X11 development headers and
libraries. On Debian/Ubuntu, install them with:

```sh
sudo apt install libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev \
  libxi-dev libxxf86vm-dev
```

Pass a `.nims` model path to open it in the interactive OpenGL viewport:

```sh
nimble run nimcad -- examples/01_hola_mundo.nims
./bin/nimcad examples/01_hola_mundo.nims
# Or use the default example:
./bin/nimcad
```

The viewport supports middle-button drag to orbit, Shift+middle-button drag to
pan, the wheel to zoom, and Esc to close. The line-oriented modeling DSL
supports zero-argument procedures, parameters, spheres, boxes, cylinders,
boolean and smooth operations, finite and polar repetition, sinusoidal
displacement, twisting, rounding, coloring, and transforms. It does not execute
arbitrary NimScript. The broader Merenda CAD interface is not part of this
viewport yet.

### Example scripts

- `examples/01_hola_mundo.nims`
- `examples/02_brida_parametrica.nims`
- `examples/03_giroide_organico.nims`
- `examples/04_disipador_calor.nims`
