{ lib
, buildPythonPackage
, fetchFromGitHub
, pythonOlder
, einops
, numpy
, torch
, torchaudio
, tqdm
, pytestCheckHook
, fetchPypi
, setuptools
, descript-audiotools
, docstring-parser
, argbind
}:
buildPythonPackage rec {
  pname = "descript-audio-codec";
  version = "1.0.0";
  format = "setuptools";

  disabled = pythonOlder "3.7";

  src = fetchFromGitHub {
    owner = "descriptinc";
    repo = "descript-audio-codec";
    rev = version;
    hash = "sha256-cABV+wyon211I2Gvhu0hn+Y1D/RiQ6pjxU7qYMN71BU=";
  };

  build-system = [
    setuptools
  ];

  propagatedBuildInputs = [
    argbind
    einops
    numpy
    torch
    torchaudio
    tqdm
    descript-audiotools
  ];

  nativeCheckInputs = [
    pytestCheckHook
  ];

  # Tests require internet connection to download model weights
  doCheck = false;

  pythonImportsCheck = [ "dac" ];

  meta = with lib; {
    description = "A high-quality general neural audio codec";
    longDescription = ''
      Descript Audio Codec (.dac) is a high fidelity general neural audio codec
      that can compress 44.1 KHz audio into discrete codes at a low 8 kbps bitrate.
      It achieves approximately 90x compression while maintaining exceptional fidelity
      and minimizing artifacts. The universal model works on all audio domains
      (speech, environment, music, etc.).
    '';
    homepage = "https://github.com/descriptinc/descript-audio-codec";
    changelog = "https://github.com/descriptinc/descript-audio-codec/releases/tag/${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
