{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  uv-dynamic-versioning,
  hatchling,
}:

buildPythonPackage rec {
  pname = "pydantic-ai";
  version = "0.0.53";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pydantic";
    repo = "pydantic-ai";
    tag = "v${version}";
    hash = "sha256-PLNZa3oOhWALpAPw+HeiMW02RTuCx3hyqJ/PU6pNLj0=";
  };

  # postPatch = ''
  #   substituteInPlace pyproject.toml \
  #     --replace-fail ', "uv-dynamic-versioning"' "" \
  #     --replace-fail 'dynamic = ["version"]' 'version = "${version}"'
  # '';

  pythonRelaxDeps = [
    "uv-dynamic-versioning"
  ];

  build-system = [
    hatchling
    uv-dynamic-versioning
  ];

  nativeBuildInputs = [
    uv-dynamic-versioning
  ];

  dependencies = [
    uv-dynamic-versioning
  ];

  doCheck = true;

  pythonImportsCheck = [
    "pydantic_ai"
  ];

  meta = {
    description = "Finetune Llama 3.3, DeepSeek-R1 & Reasoning LLMs 2x faster with 70% less memory";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ hoh ];
  };
}
