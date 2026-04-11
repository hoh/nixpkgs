{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  poetry-core,

  # dependencies
  fastapi,
  psutil,
  pydantic,
  typing-inspect,

  # optional-dependencies
  pydantic-settings,
  sqlalchemy,

  # tests
  httpx,
  pytest-asyncio,
  pytest-timeout,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "fastapi-utils";
  version = "0.8.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "dmontagu";
    repo = "fastapi-utils";
    tag = version;
    hash = "sha256-MvwvR+6DPHPg6ceaGh8h7VAGrAKhGCa/jhRQuHfFaf4=";
  };

  build-system = [
    poetry-core
  ];

  # nixpkgs carries a newer psutil than upstream's upper bound, and the package
  # only uses stable public APIs for its timing middleware.
  pythonRelaxDeps = [
    "psutil"
  ];

  dependencies = [
    fastapi
    psutil
    pydantic
    typing-inspect
  ];

  optional-dependencies = {
    all = [
      pydantic-settings
      sqlalchemy
      typing-inspect
    ];
    session = [
      sqlalchemy
    ];
  };

  nativeCheckInputs = [
    httpx
    pytest-asyncio
    pytest-timeout
    pytestCheckHook
  ]
  ++ optional-dependencies.all;

  disabledTestPaths = [
    # The tests mount APIRouter directly as an ASGI app, which is no longer
    # supported by the FastAPI/Starlette stack in nixpkgs.
    "tests/test_cbv.py"
  ];

  pythonImportsCheck = [
    "fastapi_utils"
    "fastapi_utils.cbv"
    "fastapi_utils.tasks"
    "fastapi_utils.timing"
  ];

  meta = {
    description = "Reusable utilities for FastAPI";
    homepage = "https://fastapiutils.github.io/fastapi-utils/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ hoh ];
  };
}
