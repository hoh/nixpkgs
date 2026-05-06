{
  lib,
  buildPythonPackage,
  fetchPypi,
  pythonOlder,

  # build-system
  setuptools,

  # dependencies
  librosa,
  numpy,
  pyyaml,
  scipy,
  torch,
  torchaudio,
}:

buildPythonPackage rec {
  pname = "resemble-perth";
  version = "1.0.1";
  disabled = pythonOlder "3.8";
  format = "setuptools";

  src = fetchPypi {
    pname = "resemble_perth";
    inherit version;
    hash = "sha256-5GiM/CLgeyrOVnuYfrLCbkrBnLw3+/rP1nlKKTOtI5I=";
  };

  propagatedBuildInputs = [
    librosa
    numpy
    pyyaml
    scipy
    setuptools
    torch
    torchaudio
  ];

  doCheck = false;

  preCheck = ''
    export NUMBA_DISABLE_CACHE=1
  '';

  meta = {
    description = "Audio Watermarking and Detection Library";
    homepage = "https://github.com/resemble-ai/Perth";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
