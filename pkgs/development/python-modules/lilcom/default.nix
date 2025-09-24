# pkgs/development/python-modules/lilcom/default.nix
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  cmake,
  ninja,
  numpy,
  pytestCheckHook,
  pybind11,
}:

buildPythonPackage rec {
  pname = "lilcom";
  version = "1.8.0";

  format = "setuptools"; # setup.py drives a CMake-built extension
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "danpovey";
    repo = "lilcom";
    rev = "v${version}";
    hash = "sha256-y0E4j6FhJvnyevGf0cwnhNO3tJwcNs2CzEQBaLNR6p4=";
  };

  # Tools for the C++ extension and pybind11 config package
  nativeBuildInputs = [
    setuptools
    cmake
    ninja
    pybind11
  ];
  buildInputs = [ numpy ];
  propagatedBuildInputs = [ numpy ];

  # Prevent stdenv's CMake hooks from taking over the build (the project has no
  # 'install' target; Python packaging handles installation)
  dontUseCmakeConfigure = true;
  dontUseCmakeBuild = true;
  dontUseCmakeInstall = true;

  # Replace upstream FetchContent of pybind11 with a system package lookup
  postPatch = ''
        cat > cmake/pybind11.cmake <<'EOF'
    find_package(pybind11 CONFIG REQUIRED)
    # Upstream's downloader is replaced by a no-op. Targets are provided by pybind11.
    EOF
  '';

  # Help modern pybind11 configure Python cleanly (avoids CMP0148 warning)
  env.CMAKE_ARGS = "-DPYBIND11_FINDPYTHON=ON";

  nativeCheckInputs = [ pytestCheckHook ];
  pythonImportsCheck = [ "lilcom" ];

  meta = with lib; {
    description = "Lossy-compression utility for NumPy arrays";
    homepage = "https://github.com/danpovey/lilcom";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
    changelog = "https://github.com/danpovey/lilcom/tags";
  };
}
