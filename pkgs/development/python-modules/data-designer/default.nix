{
  lib,
  buildPythonPackage,
  fetchPypi,

  hatchling,
  uv-dynamic-versioning,

  data-designer-config,
  data-designer-engine,
  prompt-toolkit,
  typer,
}:

buildPythonPackage rec {
  pname = "data-designer";
  version = "0.5.4";
  pyproject = true;

  src = fetchPypi {
    pname = "data_designer";
    inherit version;
    hash = "sha256-Q/IgE+gqret4vKEhBNvkG802CIfPp8jPbCkYdlPaGMg=";
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
    data-designer-config
    data-designer-engine
    prompt-toolkit
    typer
  ];

  pythonImportsCheck = [
    "data_designer.cli.main"
    "data_designer.interface"
  ];

  meta = {
    description = "General framework for synthetic data generation";
    homepage = "https://github.com/NVIDIA-NeMo/DataDesigner";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ hoh ];
    mainProgram = "data-designer";
    platforms = lib.platforms.unix;
  };
}
