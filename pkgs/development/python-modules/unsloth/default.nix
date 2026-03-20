{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  callPackage,
  setuptools,
  setuptools-scm,

  # dependencies
  bitsandbytes,
  numpy,
  packaging,
  psutil,
  torch,
  unsloth-zoo,
  xformers,
  transformers,
  datasets,
  sentencepiece,
  tqdm,
  accelerate,
  trl,
  peft,
  protobuf,
  huggingface-hub,
  hf-transfer,
  diffusers,
  torchvision,

  # tests
  fetchFromHuggingFace,
  fetchFromGitHub,
  cudaPackages,
  python,
  gcc,
  runCommand,
  writableTmpDirAsHomeHook,
}:

buildPythonPackage (finalAttrs: {
  pname = "unsloth";
  version = "2026.4.5";
  pyproject = true;

  # Tags on the GitHub repo don't match
  src = fetchPypi {
    pname = "unsloth";
    inherit (finalAttrs) version;
    hash = "sha256-35+IMV/WHVi0iGnOxtfSZNKo0+0ZlNVlbNtA5tXw9sE=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["setuptools==80.9.0", "setuptools-scm==9.2.0"]' \
                     'requires = ["setuptools", "setuptools-scm"]'

    # Upstream's datasets guard says only 4.4.0 and 4.4.1 recurse, but the
    # current check blocks the whole 4.4.0 .. 4.5.0 range. Narrow it to the
    # versions the upstream comment actually calls out.
    substituteInPlace unsloth/import_fixes.py \
      --replace-fail 'if (datasets_version <= Version("4.5.0")) and (' \
                     'if (datasets_version <= Version("4.4.1")) and ('

    # Strip AGPL-licensed CLI, Studio, and grouped-GEMM sources from the
    # Apache-licensed Python package.
    rm -rf \
      unsloth_cli \
      studio \
      unsloth/kernels/moe \
      COPYING

    # Drop the entry point after removing the CLI package above.
    sed -i '/^\[project\.scripts\]/,/^$/d' pyproject.toml
  '';

  prePatch = ''
    sed -i '/^import warnings, subprocess, inspect, psutil, os, math$/a \
try:\
    from transformers.utils import auto_docstring\
except Exception:\
    def auto_docstring(*args, **kwargs):\
        def _identity(func):\
            return func\
\
        return _identity\
try:\
    from huggingface_hub.dataclasses import strict\
except Exception:\
    def strict(func):\
        return func\
try:\
    from transformers.utils.type_validators import interval\
except Exception:\
    def interval(*args, **kwargs):\
        def _inner(*inner_args, **inner_kwargs):\
            if "default" in inner_kwargs:\
                return inner_kwargs["default"]\
            if inner_args:\
                return inner_args[0]\
            return None\
\
        return _inner\
' unsloth/models/_utils.py
  '';
  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    bitsandbytes
    numpy
    packaging
    psutil
    torch
    unsloth-zoo
    xformers
    transformers
    datasets
    sentencepiece
    tqdm
    accelerate
    trl
    peft
    protobuf
    huggingface-hub
    hf-transfer
    diffusers
    torchvision
  ];

  # pyproject.toml pins obsolete versions for several runtime deps.
  # Upstream issue: https://github.com/unslothai/unsloth-zoo/pull/68
  pythonRelaxDeps = [
    "datasets"
    "protobuf"
    "trl"
    "transformers"
    "torch"
  ];

  # Upstream currently lists CLI/studio dependencies as runtime requirements,
  # but they are not part of the packaged library here.
  pythonRemoveDeps = [
    "tyro"
    "wheel"
    "typer"
    "pydantic"
    "pyyaml"
    "nest-asyncio"
  ];

  # The source repository contains no test
  doCheck = false;

  # Importing requires a GPU, else the following error is raised:
  # NotImplementedError: Unsloth: No NVIDIA GPU found? Unsloth currently only supports GPUs!
  dontUsePythonImportsCheck = true;

  passthru.tests = callPackage ./tests.nix {
    unsloth = finalAttrs.finalPackage;
    inherit
      cudaPackages
      fetchFromGitHub
      fetchFromHuggingFace
      gcc
      python
      runCommand
      unsloth-zoo
      writableTmpDirAsHomeHook
      ;
  };

  meta = {
    description = "Finetune Llama 3.3, DeepSeek-R1 & Reasoning LLMs 2x faster with 70% less memory";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ hoh ];
  };
})
