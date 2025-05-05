{ lib
, stdenv
, buildPythonPackage
, fetchFromGitHub
, python3Packages
, pythonOlder
, hatchling
, descript-audio-codec
, gradio
, huggingface-hub
, numpy
, pydantic
, safetensors
, soundfile
, torch
, torchaudio
, triton
, ninja
, packaging
}:

buildPythonPackage rec {
  pname = "dia-tts";
  version = "0.1.0";
  format = "pyproject";

  disabled = pythonOlder "3.10";

  src = fetchFromGitHub {
    owner = "nari-labs";
    repo = "dia";
    rev = "7cf50c889c6013f74326cbdcb7696a985a4cf9c1";
    sha256 = "sha256-gigEUsJwaDJXuvxUY/yhv1pljzP7clziSK9HiX481uc=";
  };

  nativeBuildInputs = [
    hatchling
  ];

  propagatedBuildInputs = [
    descript-audio-codec
    gradio
    huggingface-hub
    numpy
    pydantic
    safetensors
    soundfile
    torch
    torchaudio
  ] ++ lib.optionals stdenv.isLinux [
    triton
  ];

  passthru.optional-dependencies = {
    dev = [
      ninja
      packaging
    ];
  };

  pythonRelaxDeps = [
    "gradio"
    "pydantic"
    "safetensors"
    "torch"
    "torchaudio"
    "triton"
  ];

  pythonImportsCheck = [ "dia" ];

  meta = with lib; {
    description = "Dia - A text-to-speech model for dialogue generation";
    homepage = "https://github.com/nari-labs/dia";
    license = licenses.asl20;
    maintainers = with maintainers; [ ]; # Add your name if you're the maintainer
    mainProgram = "dia";
    platforms = platforms.all;
  };
}
