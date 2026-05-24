{
  lib,
  buildPythonPackage,
  fetchPypi,

  hatchling,
  uv-dynamic-versioning,

  email-validator,
  jinja2,
  numpy,
  pandas,
  pillow,
  pyarrow,
  pydantic,
  pygments,
  python-json-logger,
  pyyaml,
  requests,
  rich,
}:

buildPythonPackage rec {
  pname = "data-designer-config";
  version = "0.5.4";
  pyproject = true;

  src = fetchPypi {
    pname = "data_designer_config";
    inherit version;
    hash = "sha256-h00ld8bNqNMavFJGwiWVFd05Yv0gmH16xs6e8jGYKVY=";
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
    email-validator
    jinja2
    numpy
    pandas
    pillow
    pyarrow
    pydantic
    pygments
    python-json-logger
    pyyaml
    requests
    rich
  ];

  # Upstream pins these to the latest release-line ranges, but nixpkgs keeps
  # compatible versions outside those bounds and the import checks cover the
  # modules used by Data Designer.
  pythonRelaxDeps = [
    "pyarrow"
    "python-json-logger"
  ];

  pythonImportsCheck = [
    "data_designer.config"
    "data_designer.plugin_manager"
  ];

  meta = {
    description = "Configuration layer for Data Designer synthetic data generation";
    homepage = "https://github.com/NVIDIA-NeMo/DataDesigner";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ hoh ];
    platforms = lib.platforms.unix;
  };
}
