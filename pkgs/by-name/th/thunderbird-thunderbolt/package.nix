{
  lib,
  stdenv,
  fetchFromGitHub,
  nixosTests,
  rustPlatform,

  bun,
  cargo-tauri,
  glib-networking,
  libappindicator-gtk3,
  nodejs,
  openssl,
  pkg-config,
  webkitgtk_4_1,
  wrapGAppsHook4,
  writableTmpDirAsHomeHook,

  bypassWaitlist ? false,
  e2eeEnabled ? true,
  skipOnboarding ? false,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "thunderbird-thunderbolt";
  version = "0.1.92";

  src = fetchFromGitHub {
    owner = "Thunderbird";
    repo = "thunderbolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-12QT+1v4ptEsNFg3IS7x6ldM9E26K8Ix+xYbC/hSncI=";
  };

  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  node_modules = stdenv.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;
    dontPatchShebangs = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --force \
        --no-progress \
        --frozen-lockfile \
        --ignore-scripts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -R node_modules $out

      runHook postInstall
    '';

    outputHash =
      {
        x86_64-linux = "sha256-riO66O8oI1fFsmBKVlEqImCvEShenFST0EKUp1rhdls=";
      }
      .${stdenv.hostPlatform.system}
        or (throw "${finalAttrs.pname}: platform ${stdenv.hostPlatform.system} is not packaged yet.");
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    cargo-tauri.hook
    bun
    nodejs
    pkg-config
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wrapGAppsHook4
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    glib-networking
    libappindicator-gtk3
    openssl
    webkitgtk_4_1
  ];

  postPatch = ''
    substituteInPlace src-tauri/.cargo/config.toml \
      --replace-fail 'rustc-wrapper = "sccache"' "" \
      --replace-fail 'rustflags = ["-C", "target-cpu=native"]' 'rustflags = []'

    substituteInPlace package.json \
      --replace-fail '"prepare": "husky",' '"prepare": "true",'

    # The safari-tauri PowerSync config references worker URLs that are not
    # served by the packaged Linux Tauri app.
    substituteInPlace src/db/powersync/database.ts \
      --replace-fail "return 'safari-tauri'" "return 'default'"

    substituteInPlace src-tauri/tauri.conf.json \
      --replace-fail \
        "http://localhost:8000 http://localhost:11434" \
        "http://localhost:8000 http://localhost:11434 http://localhost:8080 http://127.0.0.1:8080"

    substituteInPlace src-tauri/capabilities/default.json \
      --replace-fail \
        '          "url": "http://localhost:11434"' \
        '          "url": "http://localhost:11434"
        },
        {
          "url": "http://localhost:8080"
        },
        {
          "url": "http://127.0.0.1:8080"'
  '';

  configurePhase = ''
    runHook preConfigure

    cp -R ${finalAttrs.node_modules} node_modules
    chmod -R u+rw node_modules
    chmod -R u+x node_modules/.bin
    patchShebangs node_modules

    export PATH="$PWD/node_modules/.bin:$PATH"

    runHook postConfigure
  '';

  env = {
    VITE_BYPASS_WAITLIST = lib.boolToString bypassWaitlist;
    VITE_E2EE_ENABLED = lib.boolToString e2eeEnabled;
    VITE_SKIP_ONBOARDING = lib.boolToString skipOnboarding;
  };

  tauriConf = builtins.toJSON {
    bundle.createUpdaterArtifacts = false;
  };

  preBuild = ''
    tauriConfPath="$TMPDIR/tauri.conf.json"
    printf "%s" "$tauriConf" > "$tauriConfPath"
    tauriBuildFlags+=(
      "--config"
      "$tauriConfPath"
    )
  '';

  postInstall = ''
    mkdir -p "$out/share/thunderbird-thunderbolt"
    cp -R dist "$out/share/thunderbird-thunderbolt/dist"
  '';

  doCheck = false;

  passthru.tests.integration = nixosTests.thunderbird-thunderbolt;

  __structuredAttrs = true;

  meta = {
    description = "AI client from Thunderbird for local, on-prem, and cloud models";
    homepage = "https://github.com/Thunderbird/thunderbolt";
    changelog = "https://github.com/Thunderbird/thunderbolt/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ hoh ];
    mainProgram = "thunderbolt";
    platforms = [ "x86_64-linux" ];
  };
})
