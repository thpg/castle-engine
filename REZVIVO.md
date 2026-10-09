# REZVIVO engine branch

The `rezvivo` branch contains the Castle Game Engine changes used by
[REZVIVO](https://github.com/thpg/rezvivo). Its initial upstream base is
`3ff3cf21a38183c5853b5c49fd3fe61569bb3c03`.

Changes cover shared shader programs and per-draw uniforms, GPU rider animation,
lighting and shadows, scene retirement, culling and rendering instrumentation,
and asynchronous download handling. Shader sources and their generated Pascal
includes are versioned together. Upstream licenses and copyright notices apply.

REZVIVO pins a reviewed commit in `dependencies/engine.json`. Check out that
commit when building the application; no separate patch application is needed.
The upstream `master` branch remains available independently of this branch.
