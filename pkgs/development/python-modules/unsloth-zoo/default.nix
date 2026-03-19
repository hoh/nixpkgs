{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  accelerate,
  cut-cross-entropy,
  datasets,
  filelock,
  hf-transfer,
  huggingface-hub,
  msgspec,
  numpy,
  packaging,
  peft,
  pillow,
  protobuf,
  psutil,
  regex,
  sentencepiece,
  torch,
  torchao,
  triton,
  tqdm,
  transformers,
  trl,
  typing-extensions,

  # tests
  cudaPackages,
  python,
}:

let
  basePythonPackages = python.pkgs;
  gpuPython =
    let
      self = python.override {
        packageOverrides =
          final: prev: {
            torch = basePythonPackages.torchWithCuda;
            triton = basePythonPackages.triton-cuda;
          };
        inherit self;
      };
    in
    self;
in

buildPythonPackage (finalAttrs: {
  pname = "unsloth-zoo";
  version = "2026.4.7";
  pyproject = true;

  # no tags on GitHub
  src = fetchPypi {
    pname = "unsloth_zoo";
    inherit (finalAttrs) version;
    hash = "sha256-jJ58d2+5lEALEaASELZtQkY2YxNWaLrfLvOCUGnwrh4=";
  };

  prePatch = ''
    # The PyPI sdist ships these files with CRLF line endings, so normalize
    # them before applying the local source edits below.
    sed -i 's/\r$//' \
      unsloth_zoo/__init__.py \
      unsloth_zoo/device_type.py

    # Avoid a circular dependency during import in nixpkgs: `unsloth-zoo`
    # should remain importable on its own even though `unsloth` depends on it.
    sed -i '/if find_spec("unsloth") is None:/,+1d' unsloth_zoo/__init__.py
    sed -i '/if not ("UNSLOTH_IS_PRESENT" in os.environ):/,+1d' unsloth_zoo/__init__.py
  '';
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        "setuptools==80.9.0" \
        "setuptools" \
      --replace-fail \
        "setuptools-scm==9.2.0" \
        "setuptools-scm"
  '';

  pythonRelaxDeps = [
    "datasets"
    "torch"
    "transformers"
  ];

  pythonRemoveDeps = [
    "tyro"
    "wheel"
  ];

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    accelerate
    cut-cross-entropy
    datasets
    filelock
    hf-transfer
    huggingface-hub
    msgspec
    numpy
    packaging
    peft
    pillow
    protobuf
    psutil
    regex
    sentencepiece
    torch
    torchao
    triton
    tqdm
    transformers
    trl
    typing-extensions
  ];

  # No tests
  doCheck = false;

  # Importing touches torch.cuda at module import time and queries GPU memory.
  dontUsePythonImportsCheck = true;

  # Cover the import path on GPU-enabled runners instead of pure builders.
  passthru.gpuCheck =
    (cudaPackages.writeGpuTestPython.override { python3Packages = gpuPython.pkgs; }
      {
        libraries = ps: [ ps.unsloth-zoo ];
      }
      ''
        import torch

        assert torch.cuda.is_available(), "CUDA is not available"
        assert torch.ones(1, device="cuda").is_cuda

        import unsloth_zoo  # noqa: F401
        from unsloth_zoo.device_type import DEVICE_COUNT, DEVICE_TYPE

        assert DEVICE_TYPE == "cuda", DEVICE_TYPE
        assert DEVICE_COUNT > 0, DEVICE_COUNT
        print(f"Unsloth Zoo detected {DEVICE_COUNT} CUDA device(s)")
      ''
    ).gpuCheck;

  meta = {
    description = "Utils for Unsloth";
    homepage = "https://github.com/unslothai/unsloth_zoo";
    license = lib.licenses.lgpl3Plus;
    maintainers = with lib.maintainers; [ hoh ];
  };
})
