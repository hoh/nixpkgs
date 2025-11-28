{ lib
, stdenv
, stdenvNoCC
, fetchFromGitHub
, nodejs_22
, yarn-berry_4
, clojure
, jdk21_headless
, babashka
, makeWrapper
, rsync
, python3
, git
, cacert
, patchelf
, playwright-driver
, nixosTests
}:

let
  version = "2.11.1";
  src = fetchFromGitHub {
    owner = "penpot";
    repo = "penpot";
    rev = "2.11.1";
    hash = "sha256-aQF9Lg7oZIRV0GXFAYEFo2RTlZSfQ1U8mLbW48oTcr4=";
  };

  yarn-berry = yarn-berry_4;

  penpotPatches = [ ./patches/offline-friendly.patch ];

  penpotTemplates = fetchFromGitHub {
    owner = "penpot";
    repo = "penpot-files";
    rev = "103b6b7eef405cccd98737b5b4d1b459d70d2a58";
    hash = "sha256-Ix4WZqjdw7TcOjUcIzcMQiYt/2Kp2qfhxb6KslR3+xQ=";
  };

  certEnv = ''
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export GIT_SSL_CAINFO=$SSL_CERT_FILE
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE
  '';

  frontendOfflineCache = yarn-berry.fetchYarnBerryDeps {
    inherit src;
    yarnLock = "frontend/yarn.lock";
    missingHashes = ./frontend-missing-hashes.json;
    patches = penpotPatches;
    hash = "sha256-nSs/z1ushGR+YPQ24sM+0XcqDE5Kak+O2gtd0Bp+tGM=";
  };

  exporterOfflineCache = yarn-berry.fetchYarnBerryDeps {
    inherit src;
    yarnLock = "exporter/yarn.lock";
    missingHashes = ./exporter-missing-hashes.json;
    patches = penpotPatches;
    hash = "sha256-dZh+S7IIbWfP9BysqJFVmiuhcxBHCgvfNCN1uoFdqiI=";
  };

  clojureDeps = stdenvNoCC.mkDerivation {
    pname = "penpot-clojure-deps";
    inherit version;
    nativeBuildInputs = [ clojure jdk21_headless git ];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Rm48ycvyTgHy6X2vDQWRGzC+Wi32ks43nE0ZZTg1Rcw=";
    dontUnpack = true;
    dontFixup = true;
    dontPatchShebangs = true;
    dontStrip = true;
    buildCommand = ''
      set -euo pipefail
      ${certEnv}

      cp -r ${src} source
      chmod -R u+w source
      cd source
      ${lib.concatMapStrings (p: "patch -p1 < ${p}\n") penpotPatches}

      export HOME=$TMPDIR/home
      mkdir -p "$HOME/.m2" "$HOME/.gitlibs"
      export GITLIBS=$HOME/.gitlibs
      export MAVEN_OPTS="-Dmaven.repo.local=$HOME/.m2/repository"
      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME -XX:+IgnoreUnrecognizedVMOptions"
      export GIT_TERMINAL_PROMPT=0

      clojure -Srepro -P -Sdeps '{:deps {org.clojure/clojure {:mvn/version "1.12.3"} org.slf4j/slf4j-api {:mvn/version "1.7.36"} org.apache.httpcomponents/httpcore {:mvn/version "4.4.15"} commons-codec/commons-codec {:mvn/version "1.11"}}}'

      clone_gitlib() {
        local repoPath=$1
        local refType=$2
        local ref=$3
        local dest="$HOME/.gitlibs/_repos/https/github.com/''${repoPath}"

        mkdir -p "$(dirname "$dest")"
        if [ -d "$dest" ]; then
          return
        fi

        local url="https://github.com/''${repoPath}.git"
        if [ "$refType" = tag ]; then
          git clone --bare --branch "$ref" --depth 1 "$url" "$dest"
        else
          git clone --bare "$url" "$dest"
          git -C "$dest" fetch --depth 1 origin "$ref"
        fi
      }

      clone_gitlib penpot/im4java tag 1.4.0-penpot-2
      clone_gitlib funcool/yetti tag v11.8
      clone_gitlib funcool/promesa rev 46048fc0d4bf5466a2a4121f5d52aefa6337f2e8
      clone_gitlib funcool/datoteka tag 4.0.0
      clone_gitlib funcool/potok tag v2.2
      clone_gitlib funcool/beicon tag v2.2
      clone_gitlib funcool/rumext tag v2.24
      clone_gitlib noprompt/garden rev 05590ecb5f6fa670856f3d1ab400aa4961047480

      cd backend
      clojure -Srepro -P
      clojure -Srepro -P -M:build
      clojure -Srepro -T:build jar
      cd ../exporter
      clojure -Srepro -P
      clojure -Srepro -P -M:dev:shadow-cljs
      cd ../frontend
      clojure -Srepro -P
      clojure -Srepro -P -M:dev:shadow-cljs
      cd ..

      mkdir -p $out
      cp -r $HOME/.m2 $out/.m2
      cp -r $HOME/.gitlibs $out/.gitlibs
      find $out/.gitlibs/_repos -name .git -type d -prune -exec rm -rf {} +
      find $out/.gitlibs/_repos -name hooks -type d -prune -exec rm -rf {} +
      rm -rf $out/nix-support
    '';
  };

in
rec {
  inherit version src;

  penpot-backend = stdenv.mkDerivation {
    pname = "penpot-backend";
    inherit version src;
    patches = penpotPatches;
    passthru.tests = { inherit (nixosTests) penpot; };
    nativeBuildInputs = [
      clojure
      jdk21_headless
      babashka
      makeWrapper
      rsync
      python3
      git
    ];

    buildPhase = ''
      runHook preBuild
      ${certEnv}

      export HOME=$TMPDIR/home
      mkdir -p "$HOME/.m2" "$HOME/.gitlibs"
      cp -r ${clojureDeps}/.m2 "$HOME"/
      cp -r ${clojureDeps}/.gitlibs "$HOME"/
      chmod -R u+w "$HOME/.m2" "$HOME/.gitlibs"
      export GITLIBS=$HOME/.gitlibs
      export MAVEN_OPTS="-Dmaven.repo.local=$HOME/.m2/repository"
      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME -XX:+IgnoreUnrecognizedVMOptions"

      patchShebangs backend/scripts

      rm -rf backend/builtin-templates
      mkdir -p backend/builtin-templates
      cp -r ${penpotTemplates}/. backend/builtin-templates/

      cd backend
      ./scripts/build ${version}
      cd ..

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/penpot/backend
      cp -r backend/target/dist/. $out/share/penpot/backend/
      makeWrapper $out/share/penpot/backend/run.sh $out/bin/penpot-backend \
        --chdir $out/share/penpot/backend \
        --set JAVA_HOME ${jdk21_headless} \
        --set JAVA_CMD ${jdk21_headless}/bin/java

      runHook postInstall
    '';

    meta = with lib; {
      description = "Collaborative design and prototyping platform (backend)";
      homepage = "https://penpot.app";
      license = licenses.agpl3Only;
      platforms = platforms.linux;
      maintainers = with maintainers; [ hoh ];
      mainProgram = "penpot-backend";
    };
  };

  penpot-frontend = stdenv.mkDerivation {
    pname = "penpot-frontend";
    inherit version src;
    patches = penpotPatches;

    offlineCache = frontendOfflineCache;
    missingHashes = ./frontend-missing-hashes.json;

    nativeBuildInputs = [
      yarn-berry
      yarn-berry.yarnBerryConfigHook
      nodejs_22
      clojure
      jdk21_headless
      rsync
      patchelf
      python3
      git
    ];

    env = {
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_BROWSERS_PATH = playwright-driver.browsers;
      YARN_ENABLE_IMMUTABLE_INSTALLS = "true";
      YARN_NODE_LINKER = "node-modules";
      YARN_ENABLE_SCRIPTS = "0";
    };

    configurePhase = ''
      runHook preConfigure
      cd frontend
      runHook postConfigure
      cd ..
    '';

    buildPhase = ''
      runHook preBuild
      ${certEnv}
      cd frontend

      export HOME=$TMPDIR/home
      mkdir -p "$HOME/.m2" "$HOME/.gitlibs"
      cp -r ${clojureDeps}/.m2 "$HOME"/
      cp -r ${clojureDeps}/.gitlibs "$HOME"/
      chmod -R u+w "$HOME/.m2" "$HOME/.gitlibs"
      export GITLIBS=$HOME/.gitlibs
      export MAVEN_OPTS="-Dmaven.repo.local=$HOME/.m2/repository"
      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME -XX:+IgnoreUnrecognizedVMOptions"
      export GIT_TERMINAL_PROMPT=0

      patchShebangs scripts
      substituteInPlace scripts/build \
        --replace "corepack enable;" "" \
        --replace "corepack install || exit 1;" "" \
        --replace "yarn install || exit 1;" ""

      export CURRENT_HASH=${version}
      export BUILD_WASM=no
      export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
      export PLAYWRIGHT_BROWSERS_PATH=${playwright-driver.browsers}

      for dart in node_modules/sass-embedded-linux-*/dart-sass/src/dart; do
        if [ -f "$dart" ]; then
          patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} "$dart"
        fi
      done

      ./scripts/build ${version}
      cd ..
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/penpot/frontend/js
      cp -r frontend/target/dist/* $out/share/penpot/frontend/
      echo 'var penpotFlags = "";' > $out/share/penpot/frontend/js/config.js

      runHook postInstall
    '';

    meta = with lib; {
      description = "Collaborative design and prototyping platform (frontend assets)";
      homepage = "https://penpot.app";
      license = licenses.agpl3Only;
      platforms = platforms.linux;
      maintainers = with maintainers; [ hoh ];
    };
  };

  penpot-exporter = stdenv.mkDerivation {
    pname = "penpot-exporter";
    inherit version src;
    patches = penpotPatches;

    offlineCache = exporterOfflineCache;
    missingHashes = ./exporter-missing-hashes.json;

    nativeBuildInputs = [
      yarn-berry
      yarn-berry.yarnBerryConfigHook
      nodejs_22
      clojure
      jdk21_headless
      python3
      makeWrapper
      git
    ];

    env = {
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_BROWSERS_PATH = playwright-driver.browsers;
      YARN_ENABLE_IMMUTABLE_INSTALLS = "true";
      YARN_NODE_LINKER = "node-modules";
    };

    configurePhase = ''
      runHook preConfigure
      cd exporter
      runHook postConfigure
      cd ..
    '';

    buildPhase = ''
      runHook preBuild
      ${certEnv}

      export HOME=$TMPDIR/home
      mkdir -p "$HOME/.m2" "$HOME/.gitlibs"
      cp -r ${clojureDeps}/.m2 "$HOME"/
      cp -r ${clojureDeps}/.gitlibs "$HOME"/
      chmod -R u+w "$HOME/.m2" "$HOME/.gitlibs"
      export GITLIBS=$HOME/.gitlibs
      export MAVEN_OPTS="-Dmaven.repo.local=$HOME/.m2/repository"
      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME -XX:+IgnoreUnrecognizedVMOptions"

      cd exporter
      patchShebangs scripts
      substituteInPlace scripts/build \
        --replace "corepack enable;" "" \
        --replace "corepack install || exit 1;" "" \
        --replace "yarn install || exit 1;" ""

      export CURRENT_VERSION=${version}
      export NODE_ENV=production

      clojure -Srepro -M:dev:shadow-cljs release main
      cp -r node_modules target/
      cp ../.yarnrc.yml target/ || true
      cp yarn.lock target/
      cp package.json target/
      sed -i -re "s/%version%/${version}/g" ./target/app.js
      cd ..
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/penpot/exporter
      cp -r exporter/target/* $out/share/penpot/exporter/
      makeWrapper ${nodejs_22}/bin/node $out/bin/penpot-exporter \
        --chdir $out/share/penpot/exporter \
        --add-flags app.js \
        --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
        --set PLAYWRIGHT_BROWSERS_PATH ${playwright-driver.browsers}

      runHook postInstall
    '';

    meta = with lib; {
      description = "Collaborative design and prototyping platform (exporter service)";
      homepage = "https://penpot.app";
      license = licenses.agpl3Only;
      platforms = platforms.linux;
      maintainers = with maintainers; [ hoh ];
      mainProgram = "penpot-exporter";
    };
  };
}
