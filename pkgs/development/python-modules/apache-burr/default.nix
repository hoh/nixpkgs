{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,
  pythonOlder,

  # build-system
  flit-core,

  # dependencies
  aiofiles,
  click,
  fastapi,
  fastapi-utils,
  jinja2,
  loguru,
  openai,
  pydantic,
  pydantic-settings,
  requests,
  typing-inspect,
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
    tag = "v${version}";
    hash = "sha256-1hz84rzNx0UDo8F6RR9lACeRKNjyad6OgADXbcWe1zE=";
  };

  build-system = [
    flit-core
  ];

  # Upstream's CLI/server paths need Nix-specific fixes:
  # - the CLI shells out to uvicorn, so run it through the wrapped interpreter
  #   and forward sys.path for the child process;
  # - the source tarball contains the React UI sources, but the Python build
  #   does not produce burr/tracking/server/build/static, so only serve those
  #   assets when they are present.
  postPatch = ''
    substituteInPlace burr/tracking/server/run.py \
      --replace-fail 'SERVE_STATIC = os.getenv("BURR_SERVE_STATIC", "true").lower() == "true"' \
                     $'SERVE_STATIC = (\n    os.getenv("BURR_SERVE_STATIC", "true").lower() == "true"\n    and files("burr").joinpath("tracking/server/build/static").is_dir()\n)'
    substituteInPlace burr/cli/__main__.py \
      --replace-fail 'cmd = f"uvicorn burr.tracking.server.run:app --port {port} --host {host}"' \
                     'cmd = f"{sys.executable} -m uvicorn burr.tracking.server.run:app --port {port} --host {host}"'
    substituteInPlace burr/cli/__main__.py \
      --replace-fail '"BURR_BACKEND_IMPL": BACKEND_MODULES[backend],' \
                     $'"BURR_BACKEND_IMPL": BACKEND_MODULES[backend],\n        "PYTHONPATH": os.pathsep.join(sys.path),'
  '';

  # The CLI imports the tracking server, which imports bundled demo routers at
  # startup. These dependencies mirror upstream's tracking-server extra.
  dependencies = [
    aiofiles
    click
    fastapi
    fastapi-utils
    jinja2
    loguru
    openai
    pydantic
    pydantic-settings
    requests
    typing-inspect
    uvicorn
  ];

  # Upstream imports the in-app examples as burr.examples.*, but flit does not
  # install the top-level examples package. Install only the server-imported
  # modules here to avoid pulling in unrelated example entrypoints.
  postInstall = ''
    install -D examples/__init__.py "$out/${python.sitePackages}/examples/__init__.py"
    for example in email-assistant multi-modal-chatbot streaming-fastapi deep-researcher; do
      mkdir -p "$out/${python.sitePackages}/examples/$example"
      for file in __init__.py application.py server.py prompts.py utils.py; do
        if [ -e "examples/$example/$file" ]; then
          cp "examples/$example/$file" "$out/${python.sitePackages}/examples/$example/"
        fi
      done
    done
    ln -s ../examples "$out/${python.sitePackages}/burr/examples"
  '';

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

  pytestFlagsArray = [
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
    changelog = "https://github.com/apache/burr/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "burr";
    maintainers = with lib.maintainers; [ hoh ];
  };
}
