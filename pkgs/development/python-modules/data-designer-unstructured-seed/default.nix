{
  lib,
  buildPythonPackage,

  setuptools,
  wheel,

  data-designer-engine,
  mammoth,
  pandas,
  pymupdf,
  pymupdf4llm,
  unsloth,
}:

buildPythonPackage {
  pname = "data-designer-unstructured-seed";
  version = "0.1.0";
  pyproject = true;

  inherit (unsloth) src;

  sourceRoot = "unsloth-${unsloth.version}/studio/backend/plugins/data-designer-unstructured-seed";

  build-system = [
    setuptools
    wheel
  ];

  dependencies = [
    data-designer-engine
    mammoth
    pandas
    pymupdf
    pymupdf4llm
  ];

  # The plugin is loaded by Studio after studio/backend has been added to
  # sys.path. Standalone imports fail because upstream uses absolute
  # `utils.*` imports for Studio-local helpers.
  dontUsePythonImportsCheck = true;

  meta = {
    description = "Data Designer plugin for reading unstructured seed documents";
    homepage = "https://github.com/unslothai/unsloth/tree/main/studio/backend/plugins/data-designer-unstructured-seed";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ hoh ];
    platforms = lib.platforms.unix;
  };
}
