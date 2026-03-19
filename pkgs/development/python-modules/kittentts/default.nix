{
  buildPythonPackage,
  fetchFromGitHub,
  huggingface-hub,
  lib,
  misaki,
  numpy,
  onnxruntime,
  pytestCheckHook,
  pythonOlder,
  setuptools,
  soundfile,
  wheel,
  writableTmpDirAsHomeHook,
}:

buildPythonPackage rec {
  pname = "kittentts";
  version = "0.8.1";
  pyproject = true;

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "KittenML";
    repo = "KittenTTS";
    tag = version;
    hash = "sha256-X0TQP2jF5hTi045U5ggzISRsQD3e8ri+0rF7mXkbEdQ=";
  };

  postPatch = ''
    substituteInPlace kittentts/__init__.py \
      --replace-fail '__version__ = "0.1.0"' '__version__ = "${version}"'

    substituteInPlace kittentts/get_model.py \
      --replace-fail 'KittenML/kitten-tts-nano-0.1' 'KittenML/kitten-tts-nano-0.8'

    substituteInPlace pyproject.toml setup.py \
      --replace-fail '"espeakng_loader",' ""

    substituteInPlace pyproject.toml \
      --replace-fail 'license = {text = "Apache 2.0"}' 'license = "Apache-2.0"'
  '';

  build-system = [
    setuptools
    wheel
  ];

  dependencies = [
    huggingface-hub
    misaki
    numpy
    onnxruntime
    soundfile
  ]
  ++ misaki.optional-dependencies.en;

  nativeCheckInputs = [
    pytestCheckHook
    writableTmpDirAsHomeHook
  ];

  pytestFlagsArray = [ "${./test_kittentts.py}" ];

  pythonImportsCheck = [
    "kittentts"
    "kittentts.preprocess"
  ];

  meta = {
    description = "Lightweight ONNX-based text-to-speech library";
    homepage = "https://github.com/KittenML/KittenTTS";
    changelog = "https://github.com/KittenML/KittenTTS/releases/tag/${version}";
    license = lib.licenses.asl20;
    teams = [ lib.teams.tts ];
    platforms = lib.platforms.unix;
  };
}
