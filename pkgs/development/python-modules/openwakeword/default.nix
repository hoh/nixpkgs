{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools         # from python3Packages
, onnxruntime        # from python3Packages
# , tflite-runtime     # from python3Packages
}:

buildPythonPackage rec {
  pname = "openwakeword";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner  = "dscripka";
    repo   = "openWakeWord";
    rev    = "v${version}";
    sha256 = "sha256-QsXV9REAHdP0Y0fVZuU+Gt9+gcPMB60bc3DOMDYuaDM=";
  };

  nativeBuildInputs = [ setuptools ];

  propagatedBuildInputs = [
    onnxruntime     # ONNX inference backend
    # tflite-runtime  # TensorFlow Lite inference backend
  ];

  # Speex noise suppression is optional; to enable it, install the system
  # speexdsp library and add the corresponding Python wheel as a
  # propagatedBuildInput (e.g. speexdsp_ns) when needed.

  # Tests assume audio hardware; disable in Hydra if they fail
  doCheck = false;

  meta = with lib; {
    description = "An open-source audio wake word detection framework with a focus on performance and simplicity";
    homepage    = "https://github.com/dscripka/openWakeWord";
    license     = licenses.asl20;
    maintainers = with maintainers; [ hoh ];
  };
}

