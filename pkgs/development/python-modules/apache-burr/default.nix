{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pythonOlder,

  # build-system
  flit-core,

  # dependencies
  aiofiles,
  click,
  fastapi,
  fastapi-utils,
  loguru,
  pydantic,
  pydantic-settings,
  requests,
  uvicorn,

  # optional-dependencies
  aiosqlite,
  asyncpg,
  graphviz,
  haystack-ai,
  opentelemetry-api,
  opentelemetry-sdk,
  psycopg2-binary,
  pymongo,
  redis,

  # tests
  pytest-asyncio,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "apache-burr";
  version = "0.42.0";
  pyproject = true;

  # loguru's check dependency chain is no longer supported on Python 3.11 in nixpkgs.
  disabled = pythonOlder "3.12";

  src = fetchFromGitHub {
    owner = "apache";
    repo = "burr";
    tag = "v${version}-incubating";
    hash = "sha256-d5rDTMGHfpydt1F8zC+L4qGwccZ0v8NKjbPG4gHZMBk=";
  };

  build-system = [
    flit-core
  ];

  # Upstream's CLI/server paths need Nix-specific fixes:
  # - the CLI shells out to uvicorn, so forward sys.path for the child process;
  # - the Python build does not include the React UI or bundled demo routes.
  postPatch = ''
    substituteInPlace burr/tracking/server/run.py \
      --replace-fail 'SERVE_STATIC = os.getenv("BURR_SERVE_STATIC", "true").lower() == "true"' \
                     'SERVE_STATIC = os.getenv("BURR_SERVE_STATIC", "false").lower() == "true"' \
      --replace-fail $'    # dynamic importing due to the dashes (which make reading the examples on github easier)\n    email_assistant = importlib.import_module("burr.examples.email-assistant.server")\n    chatbot = importlib.import_module("burr.examples.multi-modal-chatbot.server")\n    streaming_chatbot = importlib.import_module("burr.examples.streaming-fastapi.server")\n    deep_researcher = importlib.import_module("burr.examples.deep-researcher.server")\n    counter = importlib.import_module("burr.examples.hello-world-counter.server")\n' \
                     "" \
      --replace-fail $'    # Examples -- todo -- put them behind `if` statements\n    ui_app.include_router(chatbot.router, prefix="/api/v0/chatbot")\n    ui_app.include_router(email_assistant.router, prefix="/api/v0/email_assistant")\n    ui_app.include_router(streaming_chatbot.router, prefix="/api/v0/streaming_chatbot")\n    ui_app.include_router(deep_researcher.router, prefix="/api/v0/deep_researcher")\n    ui_app.include_router(counter.router, prefix="/api/v0/counter")\n' \
                     ""
    substituteInPlace burr/cli/__main__.py \
      --replace-fail '"BURR_BACKEND_IMPL": BACKEND_MODULES[backend],' \
                     $'"BURR_BACKEND_IMPL": BACKEND_MODULES[backend],\n        "PYTHONPATH": os.pathsep.join(sys.path),'
  '';

  # Keep the default package usable for the CLI and local tracking server.
  dependencies = [
    aiofiles
    click
    fastapi
    fastapi-utils
    loguru
    pydantic
    pydantic-settings
    requests
    uvicorn
  ];

  optional-dependencies = {
    aiosqlite = [
      aiosqlite
    ];
    asyncpg = [
      asyncpg
    ];
    cli = [
      click
      loguru
      requests
    ];
    graphviz = [
      graphviz
    ];
    haystack = [
      haystack-ai
    ];
    opentelemetry = [
      opentelemetry-api
      opentelemetry-sdk
    ];
    postgresql = [
      psycopg2-binary
    ];
    psycopg2 = [
      psycopg2-binary
    ];
    pydantic = [
      pydantic
    ];
    pymongo = [
      pymongo
    ];
    redis = [
      redis
    ];
    tracking-client = [
      pydantic
    ];
  };

  nativeCheckInputs = lib.optionals (!pythonOlder "3.12") (
    [
      pytest-asyncio
      pytestCheckHook
    ]
    ++ optional-dependencies.aiosqlite
    ++ optional-dependencies.graphviz
    ++ optional-dependencies.pydantic
    ++ pydantic.optional-dependencies.email
  );

  # The pydantic check dependency chain is no longer supported on Python 3.11.
  doCheck = !pythonOlder "3.12";

  pytestFlags = [
    "tests/common"
    "tests/core"
    "tests/tracking"
    "tests/visibility"
    "tests/test_end_to_end.py"
    "tests/integrations/serde/test_pydantic.py"
    "tests/integrations/serde/test_pickle.py"
  ];

  disabledTests = [
    # Python 3.14 changed the default pickle protocol, but upstream asserts exact
    # pickle bytes rather than round-tripping the object.
    "test_serde_of_pickle_object"
  ];

  pythonImportsCheck = [
    "burr"
    "burr.cli.__main__"
    "burr.core"
    "burr.tracking.server.run"
  ];

  # The wheel exposes several console scripts. Check the generated wrappers with
  # --help so the derivation verifies entrypoint wiring without starting the
  # long-running tracking server during the build.
  postCheck = ''
    $out/bin/burr --help > /dev/null
    $out/bin/burr-test-case --help > /dev/null
  '';

  meta = {
    description = "State machine framework for building AI applications";
    homepage = "https://github.com/apache/burr";
    changelog = "https://github.com/apache/burr/releases/tag/v${version}-incubating";
    license = lib.licenses.asl20;
    mainProgram = "burr";
    maintainers = with lib.maintainers; [ hoh ];
  };
}
