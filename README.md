# Lab 4 - Zig: Carga de modelos

Carga un `.obj` triangulado (Suzanne, exportado de Blender) y lo dibuja en
wireframe: se proyectan los vértices (ortográfica, centrado y escalado) y se
traza cada arista con Bresenham. Genera `out.png` (Zig puro, sin dependencias).

```sh
zig build run              # usa model.obj
zig build run -- otro.obj  # otro modelo
```

- `src/obj.zig` — parser de `v` / `f`.
- `src/canvas.zig` — buffer de píxeles y `drawLine`.
- `src/png.zig` — encoder PNG.
- `src/main.zig` — proyección y dibujo del wireframe.
