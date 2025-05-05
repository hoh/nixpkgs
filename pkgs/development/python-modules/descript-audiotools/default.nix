{ lib
, buildPythonPackage
, fetchFromGitHub
, pythonOlder
, numpy
, pillow
, scipy
, torch
, torchaudio
, matplotlib
, pyyaml
, soundfile
, tqdm
, librosa
, numba
, resampy
, pytestCheckHook
, pytestcov
, flatten-dict
, julius
, fetchPypi
# New dependencies from setup.py
#, argbind
#, pyloudnorm
, importlib-resources
, ffmpy
, ipython
, rich
#, pystoi
#, torch-stoi
, markdown2
#, randomname
, protobuf
, tensorboard
, setuptools
, attrs
, future
, argbind
}:
let
  pyloudnorm = buildPythonPackage rec {
    pname = "pyloudnorm";
    version = "0.1.1";
    format = "pyproject";

    src = fetchFromGitHub {
      owner = "csteinmetz1";
      repo = "pyloudnorm";
      rev = "v${version}";
      hash = "sha256-eIJrN/UU1oCnBJkNzUJXNykNq7tsUpKH4GZtoU4wKUk="; # Replace with actual hash
    };

    nativeBuildInputs = [
      setuptools  # Add setuptools as a build input
      attrs
      future
    ];

    # Patch the pyproject.toml file to properly declare dynamic fields
  postPatch = ''
    if [ -f pyproject.toml ]; then
      # Add dynamic fields to fix the build errors
      substituteInPlace pyproject.toml \
        --replace '[project]' '[project]
    dynamic = ["readme", "requires-python", "license", "classifiers", "dependencies"]'
    fi
  '';


    propagatedBuildInputs = [
      scipy
      numpy
      matplotlib
      soundfile
    ];

    # Tests require audio files not included in the distribution
    doCheck = false;

    pythonImportsCheck = [ "pyloudnorm" ];
  };
  torch-stoi = buildPythonPackage rec {
    pname = "torch_stoi";
    version = "0.2.3";
    format = "setuptools";
    src = fetchFromGitHub {
      owner = "mpariente";
      repo = "pytorch_stoi";
      rev = "v${version}";
      hash = "sha256-M+ntUG3ZHjF3cAZWIJ9rwwQ9TqnMpmbc70eOgGvD9k0="; # Replace with actual hash
    };
    propagatedBuildInputs = [
      numpy
      torch
      torchaudio
      pystoi
    ];
    # Tests require audio files not included in the distribution
    doCheck = false;
    pythonImportsCheck = [ "torch_stoi" ];
    meta = with lib; {
      description = "PyTorch implementation of the Short Term Objective Intelligibility measure";
      homepage = "https://github.com/mpariente/pytorch_stoi";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
    };
  };
  pystoi = buildPythonPackage rec {
    pname = "pystoi";
    version = "0.4.1";
    format = "setuptools";
    src = fetchFromGitHub {
      owner = "mpariente";
      repo = "pystoi";
      rev = "v${version}";
      hash = "sha256-gGT0feeDotj92bd7aG3k84bLBJSoHKAWlxeLtYS8jL0="; # Replace with actual hash
    };
    propagatedBuildInputs = [
      numpy
      scipy
    ];
    # No tests included in the repository
    doCheck = false;
    pythonImportsCheck = [ "pystoi" ];
    meta = with lib; {
      description = "Python implementation of the Short Term Objective Intelligibility measure";
      homepage = "https://github.com/mpariente/pystoi";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
    };
  };
  randomname = buildPythonPackage rec {
    pname = "randomname";
    version = "0.2.1";
    format = "setuptools";
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-t5uYMCukR5FksKT4eZW3vrvR2RASrtpIM0Hj5YrOUg4=";
    };
    propagatedBuildInputs = [ ];
    # Package has no tests
    doCheck = false;
    pythonImportsCheck = [ "randomname" ];
    meta = with lib; {
      description = "Random name generator";
      homepage = "https://github.com/jjviana/randomname";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
    };
  };
in
buildPythonPackage rec {
  pname = "descript-audiotools";
  version = "0.7.4";
  format = "setuptools";
  disabled = pythonOlder "3.7";
  src = fetchFromGitHub {
    owner = "descriptinc";
    repo = "audiotools";
    rev = version;
    hash = "sha256-mDReVnVgxb+qcTosUSNG3jp6QhaIWdcddyfK4xuyxCc=";
  };
  propagatedBuildInputs = [
    # Original dependencies
    numpy
    pillow
    scipy
    torch
    torchaudio
    matplotlib
    pyyaml
    soundfile
    tqdm
    librosa
    numba
    resampy
    flatten-dict
    julius
    # New dependencies from setup.py
    argbind
    pyloudnorm
    importlib-resources
    ffmpy
    ipython
    rich
    pystoi
    torch-stoi
    markdown2
    randomname
    protobuf
    tensorboard
  ];
  nativeCheckInputs = [
    pytestCheckHook
    pytestcov
  ];
  # Tests require network access
  doCheck = false;
  pythonImportsCheck = [ "audiotools" ];
  meta = with lib; {
    description = "Object-oriented handling of audio data with GPU-powered augmentations";
    longDescription = ''
      AudioTools provides object-oriented handling of audio signals,
      with fast augmentation routines, batching, padding, and more.
      It includes utilities for audio processing, manipulation, and
      analysis with GPU acceleration support.
    '';
    homepage = "https://github.com/descriptinc/audiotools";
    changelog = "https://github.com/descriptinc/audiotools/releases/tag/${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
