{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools   # from python3Packages
, git          # from the main pkgs set
}:

buildPythonPackage rec {
  pname = "pvporcupine";
  version = "3.0.4";

  src = fetchFromGitHub {
    owner = "Picovoice";
    repo  = "porcupine";
    rev   = "${version}";
    # Replace this with the real sha256, e.g. via:
    # nix-prefetch-url --print-path \
    #   https://github.com/Picovoice/porcupine/archive/refs/tags/v${version}.tar.gz
    sha256 = "sha256-nloPeumJuBobjKS+vq1SDPO35QkvR7ye0Ig+akqUg4A=";
  };

  # src = fetchPypi {
  #   inherit pname version;
  #   sha256 = "";  # replace with actual hash via `nix-prefetch-url`
  # };

  # setup.py uses "git clean -dfx" and Python setuptools
  nativeBuildInputs = [ setuptools git ];

  # No external Python dependencies beyond stdlib
  propagatedBuildInputs = [];

  # Skip tests (they rely on audio hardware)
  doCheck = false;

  # Run setup.py from binding/python so that it can locate lib/ and resources/
  buildPhase = ''
    cd ${src}/binding/python
    python3 setup.py build
  '';

  installPhase = ''
    cd ${src}/binding/python
    python3 setup.py install \
      --prefix=$out \
      --single-version-externally-managed \
      --record=$out/record.txt
  '';

  meta = with lib; {
    description = "Porcupine wake word engine Python SDK with prebuilt binaries and resources"; 
    homepage    = "https://github.com/Picovoice/porcupine"; 
    license     = licenses.asl20; 
    maintainers = with maintainers; [ ];
  };
}

