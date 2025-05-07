{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools         # from python3Packages
, pyaudio            # from python3Packages
, faster-whisper     # from python3Packages
, pvporcupine        # from python3Packages
, webrtcvad   # from python3Packages
, halo               # from python3Packages
, torch              # from python3Packages
, torchaudio         # from python3Packages
, scipy              # from python3Packages
, openwakeword       # from python3Packages
, websockets         # from python3Packages
, websocket-client   # from python3Packages
, soundfile          # from python3Packages
}:

buildPythonPackage rec {
  pname = "realtime-stt";
  version = "0.3.104";

  src = fetchFromGitHub {
    owner = "KoljaB";
    repo  = "RealtimeSTT";
    rev   = "v${version}";
    sha256 = "sha256-cOQAPUjhjMjWeSyR3WCvW/L20w83hyCuarRhg6r4pZA=";
  };

  # needed to run setup.py
  nativeBuildInputs = [ setuptools ];

  # list each runtime Python dependency separately
  propagatedBuildInputs = [
    pyaudio
    faster-whisper
    pvporcupine
    webrtcvad
    halo
    torch
    torchaudio
    scipy
    openwakeword
    websockets
    websocket-client
    soundfile
  ];

  # tests may require microphone/audio hardware; disable if they fail in Hydra
  doCheck = false;

  meta = with lib; {
    description = "Real-time speech-to-text library with VAD and wake-word support";
    homepage    = "https://github.com/KoljaB/RealtimeSTT";
    license     = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
