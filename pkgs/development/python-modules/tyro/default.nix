{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pytestCheckHook,
  hatch,
  typeguard,
  docstring-parser,
  typing-extensions,
  rich,
  shtab,
  # Test dependencies
  attrs,
  flax,
  jax,
  ml-collections,
  omegaconf,
  pydantic,
  torch,
}:

buildPythonPackage rec {
  pname = "tyro";
  version = "0.9.19";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "brentyi";
    repo = "tyro";
    tag = "v${version}";
    hash = "sha256-A1Vplc84Xy8TufqmklPUzIdgiPpFcIjqV0eUgdKmYRM=";
  };

  build-system = [ hatch ];

  dependencies = [
    typeguard
    docstring-parser
    typing-extensions
    rich
    shtab
  ];

  nativeCheckInputs = [
    attrs
    flax
    jax
    ml-collections
    omegaconf
    pydantic
    pytestCheckHook
    torch
  ];

  pythonImportsCheck = [ "tyro" ];

  meta = {
    description = "CLI interfaces & config objects, from types";
    homepage = "https://github.com/brentyi/tyro";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ hoh ];
  };
}
