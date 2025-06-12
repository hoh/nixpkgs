{ lib
, buildPythonPackage
, fetchFromGitHub
, numpy
, torch
, torchaudio
, einops
, onnx
, tqdm
, pythonOlder
}:

buildPythonPackage rec {
  pname   = "s3tokenizer";
  version = "0.1.7";

  disabled = pythonOlder "3.8";
  format   = "setuptools";

  src = fetchFromGitHub {
    owner = "xingchensong";
    repo  = "S3Tokenizer";
    rev   = "v${version}";           # tag dc95bac • 2025-01-15 :contentReference[oaicite:0]{index=0}
    hash  = "sha256-i8ge0EQ0MP7aRYvxZZGOU+0IZpcGHxgWeJodzh0xTLY=";
  };

  propagatedBuildInputs = [
    numpy torch torchaudio einops onnx tqdm
  ];

  # upstream ships no tests; avoids heavy model downloads
  doCheck = false;
  pythonImportsCheck = [ "s3tokenizer" ];
}
