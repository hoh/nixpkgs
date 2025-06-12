{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools
, numpy
, librosa
, s3tokenizer           # <- new in nixpkgs?  add similarly if missing
, torch
, torchaudio
, transformers
, diffusers
, safetensors
, omegaconf
, pythonOlder
}:

buildPythonPackage rec {
  pname = "chatterbox-tts";
  version = "0.1.2";

  disabled = pythonOlder "3.9";
  format   = "pyproject";

  # src = fetchFromGitHub {
  #   owner = "resemble-ai";
  #   repo  = "chatterbox";
  #   # upstream has no tag yet; pin the commit that contains 0.1.2
  #   rev   = "f8fb6ec4cfa48aeca9606039761e97b4f07ad8d1";
  #   hash  = "";
  # };

  src = fetchGit {
    url = "https://forge.internal.okeso.net/sepal/chatterbox";
    name = "chatterbox";
    rev = "bc694737a8df3b58adbcef7e4ba5308a77232818";
  };

  propagatedBuildInputs = [
    numpy librosa s3tokenizer torch torchaudio
    transformers diffusers safetensors omegaconf
  ];

  # ------------------------------------------------------------------
  # Numba cannot cache inside the read-only Nix store.  Turn the cache
  # off for the import check *and* for any downstream use of chatterbox.
  # ------------------------------------------------------------------
  preCheck = ''
    export NUMBA_DISABLE_CACHE=1
  '';

  postFixup = ''
    # chatterbox is a pure lib, no console scripts by default
    # but wrap anyway in case future versions add CLI entry-points
    for f in $(find $out/bin -type f); do
      wrapProgram "$f" --set NUMBA_DISABLE_CACHE 1
    done
  '';

  # Model tests need a GPU + large downloads → skip
  doCheck = false;

  # pythonImportsCheck = [ "chatterbox" ];

  # Relax overly-strict version pins so we can use the
  # versions available in nixpkgs.
  prePatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'numpy>=1.24.0,<1.26.0' 'numpy>=1.24.0' \
      --replace-fail 'torch==2.6.0' 'torch' \
      --replace-fail 'torchaudio==2.6.0' 'torchaudio' \
      --replace-fail 'transformers==4.46.3' 'transformers' \
      --replace-fail 'diffusers==0.29.0' 'diffusers' \
      --replace-fail 'safetensors==0.5.3' 'safetensors' \
      --replace-fail '    "conformer==0.3.2",' "" \
      --replace-fail '    "spacy-pkuseg",' "" \
      --replace-fail '    "pykakasi==2.3.0",' "" \
      --replace-fail '    "gradio==5.44.1",' "" \
      --replace-fail '    "pyloudnorm",' ""
  '';
}
