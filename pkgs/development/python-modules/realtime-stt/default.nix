{ lib
, fetchFromGitHub
, buildPythonPackage
, setuptools         # from python3Packages
, pyaudio            # from python3Packages
, faster-whisper     # from python3Packages
, pvporcupine        # from python3Packages
, webrtcvad-wheels   # from python3Packages
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
    # replace with the actual sha256:
    sha256 = "0l2a1h93b4g8z5dm1r9x7vf6p5c3n8k2qb0y7w6f1zs4dj9v0c2";
  };

  # needed to run setup.py
  nativeBuildInputs = [ setuptools ];

  # list each runtime Python dependency separately
  propagatedBuildInputs = [
    pyaudio
    faster-whisper
    pvporcupine
    webrtcvad-wheels
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
