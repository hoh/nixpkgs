{
  buildPythonPackage,
  conformer,
  diffusers,
  fetchFromGitHub,
  huggingface-hub,
  librosa,
  numpy,
  python,
  pythonOlder,
  resemble-perth,
  s3tokenizer,
  safetensors,
  setuptools,
  tokenizers,
  torch,
  torchaudio,
  tqdm,
  transformers,
}:

buildPythonPackage rec {
  pname = "chatterbox-tts";
  version = "0.1.2";
  pyproject = true;

  disabled = pythonOlder "3.9";

  src = fetchFromGitHub {
    owner = "resemble-ai";
    repo = "chatterbox";
    tag = "v${version}";
    hash = "sha256-NuyiOTHmtjFz8Y+1tIVLUAWDmePyLu4PZvsGoKvMJao=";
  };

  build-system = [
    setuptools
  ];

  pythonRelaxDeps = [
    "diffusers"
    "safetensors"
    "torch"
    "torchaudio"
    "transformers"
  ];

  dependencies = [
    conformer
    diffusers
    huggingface-hub
    librosa
    numpy
    resemble-perth
    s3tokenizer
    safetensors
    tokenizers
    torch
    torchaudio
    tqdm
    transformers
  ];

  env.NUMBA_DISABLE_CACHE = "1";

  dontUsePythonImportsCheck = true;
  preDistPhases = [ "chatterboxImportsCheckPhase" ];
  chatterboxImportsCheckPhase = ''
    echo "Check whether Chatterbox modules can be imported"
    export NUMBA_CACHE_DIR="$TMPDIR/numba-cache"
    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"
    mkdir -p "$NUMBA_CACHE_DIR"
    ${python.interpreter} -c 'import chatterbox; import chatterbox.tts; import chatterbox.vc'
  '';

  postFixup = ''
    if [ -d "$out/bin" ]; then
      for f in $(find "$out/bin" -type f); do
        wrapProgram "$f" --set NUMBA_DISABLE_CACHE 1
      done
    fi
  '';

  # Model tests need a GPU and large downloads.
  doCheck = false;
}
