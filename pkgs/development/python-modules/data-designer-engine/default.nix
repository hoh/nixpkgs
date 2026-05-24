{
  lib,
  buildPythonPackage,
  fetchPypi,

  hatchling,
  uv-dynamic-versioning,

  anyascii,
  chardet,
  data-designer-config,
  duckdb,
  faker,
  fsspec,
  httpx,
  httpx-retries,
  huggingface-hub,
  json-repair,
  jsonpath-rust-bindings,
  jsonschema,
  lxml,
  marko,
  mcp,
  networkx,
  ruff,
  scipy,
  sqlfluff,
  tiktoken,
}:

buildPythonPackage rec {
  pname = "data-designer-engine";
  version = "0.5.4";
  pyproject = true;

  src = fetchPypi {
    pname = "data_designer_engine";
    inherit version;
    hash = "sha256-2W5kXtbQd8ROpZbR91Y9QMie3HYyFERlaggApfYJ3uA=";
  };

  env.UV_DYNAMIC_VERSIONING_BYPASS = version;

  # The PyPI sdist references the workspace README, which is not included.
  postPatch = ''
    touch README.md
  '';

  build-system = [
    hatchling
    uv-dynamic-versioning
  ];

  dependencies = [
    anyascii
    chardet
    data-designer-config
    duckdb
    faker
    fsspec
    httpx
    httpx-retries
    huggingface-hub
    json-repair
    jsonpath-rust-bindings
    jsonschema
    lxml
    marko
    mcp
    networkx
    ruff
    scipy
    sqlfluff
    tiktoken
  ];

  # Upstream uses tight upper bounds for fast-moving helper libraries. The
  # nixpkgs versions remain API-compatible for the validated imports and avoid
  # carrying extra pinned copies.
  pythonRelaxDeps = [
    "faker"
    "fsspec"
    "sqlfluff"
  ];

  pythonImportsCheck = [
    "data_designer.engine"
    "data_designer.engine.validation"
  ];

  meta = {
    description = "Generation engine for Data Designer synthetic data generation";
    homepage = "https://github.com/NVIDIA-NeMo/DataDesigner";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ hoh ];
    platforms = lib.platforms.unix;
  };
}
