{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools   # from python3Packages
, git
}:

buildPythonPackage rec {
  pname       = "pvporcupine";
  version     = "3.0.4";

  src = fetchFromGitHub {
    owner = "Picovoice";
    repo  = "porcupine";
    rev   = version;
    # Replace this with the real sha256 via:
    # nix-prefetch-url --unpack \
    #   https://github.com/Picovoice/porcupine/archive/refs/tags/${version}.tar.gz
    sha256 = "sha256-nloPeumJuBobjKS+vq1SDPO35QkvR7ye0Ig+akqUg4A=";
  };

  # Start build/install phases in binding/python
  sourceRoot = "source/binding/python";

  nativeBuildInputs    = [ setuptools git ];    # needed for setup.py invocation
  propagatedBuildInputs = [];               # no extra Python deps
  doCheck              = false;             # skip hardware-dependent tests

  # No custom buildPhase/installPhase needed—
  # default python build hooks will run here:
  #   python setup.py build
  #   python setup.py install ...
  
  meta = with lib; {
    description = "Porcupine wake word engine Python SDK with prebuilt binaries and resources";
    homepage    = "https://github.com/Picovoice/porcupine";
    license     = licenses.asl20;
    maintainers = with maintainers; [ ];
  };
}
