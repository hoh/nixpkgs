{
  lib,
  buildPythonPackage,
  fetchPypi,
  rustPlatform,
}:

buildPythonPackage rec {
  pname = "jsonpath-rust-bindings";
  version = "1.1.1";
  pyproject = true;

  src = fetchPypi {
    pname = "jsonpath_rust_bindings";
    inherit version;
    hash = "sha256-sGskZoCFsnkay/79/i8oJNNr5TnHZHwAruMyQrTTOF0=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = "sha256-xw20DhQquo4NdTv5zAgKAGLv+UR1I3OU8/rEiWZFo+M=";
  };

  nativeBuildInputs = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
  ];

  pythonImportsCheck = [ "jsonpath_rust_bindings" ];

  meta = {
    description = "Python bindings for jsonpath-rust";
    homepage = "https://github.com/night-crawler/jsonpath-rust-bindings";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ hoh ];
    platforms = lib.platforms.unix;
  };
}
