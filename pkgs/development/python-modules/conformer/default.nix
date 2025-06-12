{ lib
, fetchFromGitHub
, buildPythonPackage
, einops
, torch
, pythonOlder
}:

buildPythonPackage rec {
  pname   = "conformer";
  version = "0.3.2";          # latest upstream release :contentReference[oaicite:0]{index=0}

  disabled = pythonOlder "3.8";
  format   = "setuptools";

  src = fetchFromGitHub {
    owner = "lucidrains";
    repo  = "conformer";
    rev   = "0.3.2";          # git tag that matches PyPI
    hash  = "sha256-ibHlDFgWm9iW2VOYMrXssPPW2jNqnjqKo3B6wrc7cmM=";
  };

  propagatedBuildInputs = [ einops torch ];  # from setup.py :contentReference[oaicite:1]{index=1}

  doCheck = false;            # no test suite; avoids pulling big Torch wheels
  pythonImportsCheck = [ "conformer" ];
}
