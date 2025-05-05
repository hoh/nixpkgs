{ lib
, buildPythonPackage
, fetchPypi
, docstring-parser
}:

buildPythonPackage rec {
  pname = "argbind";
  version = "0.3.7";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-7hnw8qxmBJEUOjx8Wr06rInZB0UvAAM8QLrwY86l/fI=";
  };

  propagatedBuildInputs = [
    docstring-parser
  ];

  # No tests for argbind
  doCheck = false;

  meta = with lib; {
    description = "A Python library for binding command line arguments";
    homepage = "https://github.com/pseeth/argbind";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
