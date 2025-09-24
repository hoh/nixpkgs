# pkgs/development/python-modules/lhotse/default.nix
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pythonOlder,
  setuptools,
  setuptools-scm,
  wheel,

  # core runtime deps
  numpy,
  pyyaml,
  packaging,
  tqdm,
  audioread,
  soundfile,
  click,
  cytoolz,
  lilcom,
  tabulate,
  intervaltree,

  # optional extras
  torch,
  torchaudio,
  orjson,
  webdataset,
  h5py,
  dill,
  # aistore,
  smart_open,
  # opensmile,
  # multi-storage-client,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "lhotse";
  version = "1.31.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "lhotse-speech";
    repo = "lhotse";
    rev = "1.31.0";  # Tag was reused for 1.31.1
    sha256 = "sha256-ODXugoHKYYhcxq3RjQjj6+5VXIBEaQOiF0LX8cq8r8Y=";
  };

  env.LHOTSE_PREPARING_RELEASE = true;

  build-system = [
    setuptools
    setuptools-scm
    wheel
  ];

  dependencies = [
    numpy
    pyyaml
    packaging
    tqdm
    audioread
    soundfile
    click
    cytoolz
    lilcom
    tabulate
    intervaltree

    torch
    torchaudio
    orjson
    webdataset
    h5py
    dill
    smart_open
  ];

  # Import check is sufficient; upstream tests require corpora and GPU
  doCheck = false;
  pythonImportsCheck = [ "lhotse" ];

  # CLI entry point
  mainProgram = "lhotse";

  meta = with lib; {
    description = "Multimodal data preparation library for speech/audio ML";
    homepage = "https://github.com/lhotse-speech/lhotse";
    changelog = "https://pypi.org/project/lhotse/#history";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
  };
}
