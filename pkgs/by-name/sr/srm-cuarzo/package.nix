{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  libdisplay-info,
  libdrm,
  libGL,
  libinput,
  libgbm,
  seatd,
  udev,
}:
stdenv.mkDerivation (self: {
  pname = "srm-cuarzo";
  version = "0.12.0-1";
  rev = "v${self.version}";
  hash = "sha256-baLi0Upv8VMfeusy9EfeAXVxMo0KuKNC+EYg/c+tzRY=";

  src = fetchFromGitHub {
    inherit (self) rev hash;
    owner = "CuarzoSoftware";
    repo = "SRM";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    libdisplay-info
    libdrm
    libGL
    libinput
    libgbm
    seatd
    udev
  ];

  outputs = [
    "out"
    "dev"
  ];

  preConfigure = ''
    # The root meson.build file is in src/
    cd src
  '';

  meta = {
    description = "Simple Rendering Manager";
    homepage = "https://github.com/CuarzoSoftware/SRM";
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
})
