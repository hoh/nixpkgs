{
  buildPythonPackage,
  cacert,
  fetchFromHuggingFace,
  fetchFromGitHub,
  huggingface-hub,
  lib,
  misaki,
  numpy,
  onnxruntime,
  pytestCheckHook,
  python,
  pythonOlder,
  runWithHuggingFaceCache,
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

  pytestFlags = [ "${./test_kittentts.py}" ];

  pythonImportsCheck = [
    "kittentts"
    "kittentts.preprocess"
  ];

  passthru.tests.huggingface-example =
    let
      model = fetchFromHuggingFace {
        owner = "KittenML";
        repo = "kitten-tts-nano-0.8-int8";
        rev = "84781d74e29ee25217551556398b42f80593a813";
        hash = "sha256-QBb7/EYQBPLJPKDZ0GELNKt4FVjBZ8Tamw0mrqUwmtE=";
      };
      pythonEnv = python.withPackages (ps: [ ps.kittentts ]);
    in
    runWithHuggingFaceCache {
      name = "kittentts-huggingface-example";
      runtimeInputs = [ pythonEnv ];
      repositories = [ model ];
      extraEnv = {
        # `hf_hub_download` eagerly constructs an httpx client, even when the
        # seeded cache and HF_HUB_OFFLINE make the network path unnecessary.
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        REQUESTS_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      };
      command = ''
        python - <<'PY'
        from pathlib import Path

        import numpy as np
        import soundfile as sf

        from kittentts import KittenTTS

        text = "This high quality TTS model works without a GPU"
        model_id = "KittenML/kitten-tts-nano-0.8-int8"
        expected_voices = [
            "Bella",
            "Jasper",
            "Luna",
            "Bruno",
            "Rosie",
            "Hugo",
            "Kiki",
            "Leo",
        ]

        model = KittenTTS(model_id)
        assert model.available_voices == expected_voices

        audio = model.generate(text, voice="Jasper")
        assert audio.ndim == 1
        assert audio.dtype == np.float32
        assert audio.shape[0] > 24_000
        assert np.isfinite(audio).all()
        assert np.count_nonzero(audio) == audio.shape[0]
        assert float(np.std(audio)) > 0.01
        assert 0.05 < float(np.max(np.abs(audio))) < 1.0

        output = Path("output.wav")
        sf.write(output, audio, 24_000)

        saved_audio, sample_rate = sf.read(output, dtype="float32")
        assert sample_rate == 24_000
        assert saved_audio.ndim == 1
        assert saved_audio.shape == audio.shape
        assert np.isfinite(saved_audio).all()
        assert float(np.std(saved_audio)) > 0.01
        assert output.stat().st_size > 10_000
        PY

        touch "$out"
      '';
    };

  meta = {
    description = "Lightweight ONNX-based text-to-speech library";
    homepage = "https://github.com/KittenML/KittenTTS";
    changelog = "https://github.com/KittenML/KittenTTS/releases/tag/${version}";
    license = lib.licenses.asl20;
    teams = [ lib.teams.tts ];
    platforms = lib.platforms.unix;
  };
}
