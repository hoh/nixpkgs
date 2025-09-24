{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # hooks
  pythonRelaxDepsHook,

  # build system
  setuptools,
  wheel,

  # core runtime deps
  torch,
  lightning,
  hydra-core,
  omegaconf,
  numpy,
  packaging,
  pydantic,
  protobuf,
  pyyaml,
  torchmetrics,
  tqdm,
  transformers,
  sentencepiece,
  huggingface-hub,
  filelock,
  regex,

  # additional deps flagged by pythonRuntimeDepsCheck
  fsspec,
  numba,
  onnx,
  python-dateutil,
  ruamel-yaml,
  scikit-learn,
  text-unidecode,
  wget,
  wrapt,

  # Manually added
  lhoste,
}:

buildPythonPackage rec {
  pname = "nemo-toolkit";
  version = "2.4.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "NVIDIA-NeMo";
    repo = "NeMo";
    rev = "v${version}";
    # Replace with the fixed-output hash you prefetch.
    hash = "sha256-iPA4Diav89b9OptOjvAh8bOT9DIJrZeDLowet58fRa4=";
  };

  nativeBuildInputs = [
    pythonRelaxDepsHook
    setuptools
    wheel
  ];

  # Upstream pins fsspec and protobuf too tightly for nixpkgs.
  # This relaxes the version constraints in the installed dist-info.
  pythonRelaxDeps = [
    "fsspec"
    "protobuf"
  ];

  # If upstream uses setuptools_scm, keep version deterministic.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  propagatedBuildInputs = [
    # core
    torch
    lightning
    hydra-core
    omegaconf
    numpy
    packaging
    pydantic
    protobuf
    pyyaml
    torchmetrics
    tqdm
    transformers
    sentencepiece
    huggingface-hub
    filelock
    regex

    # extras that pythonRuntimeDepsCheck required
    fsspec
    python-dateutil
    ruamel-yaml
    text-unidecode
    wget
    wrapt
    numba
    onnx
    scikit-learn

    # Manually added
    lhoste
  ];

  # disabled = lib.pythonOlder "3.10";

  doCheck = false;

  pythonImportsCheck = [ "nemo" ];

  meta = with lib; {
    description = "NVIDIA NeMo framework for LLM, Multimodal, ASR, and TTS";
    homepage = "https://github.com/NVIDIA-NeMo/NeMo";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
    changelog = "https://github.com/NVIDIA-NeMo/NeMo/releases/tag/v${version}";
  };
}
