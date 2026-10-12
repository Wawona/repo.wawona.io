# Official Rust 1.93.0 host toolchain + rust-std for aarch64-linux-android.
# Termux niri uses the real Android target (Bionic std). Winit is patched to
# take the Wayland free_unix path instead of android-activity.
{ nativePkgs }:

let
  version = "1.93.0";
  hostTriple = "aarch64-apple-darwin";
  androidTriple = "aarch64-linux-android";
  rustHostSrc = nativePkgs.fetchurl {
    url = "https://static.rust-lang.org/dist/rust-${version}-${hostTriple}.tar.gz";
    hash = "sha256-4zzyN8//ivdVgf7ezp88NI6Xa7gkYHh4bxiIw7JR04A=";
  };
  rustStdAndroidSrc = nativePkgs.fetchurl {
    url = "https://static.rust-lang.org/dist/rust-std-${version}-${androidTriple}.tar.gz";
    hash = "sha256-Ka+xa/jXEX7H+2ms5q1e5PLLlj8D6JRf1t3gwdZD8Q8=";
  };
in
nativePkgs.stdenv.mkDerivation {
  pname = "rust-toolchain-android";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [ nativePkgs.gnutar nativePkgs.gzip ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out tmp-host tmp-android
    tar -xzf ${rustHostSrc} -C tmp-host
    host_root=tmp-host/rust-${version}-${hostTriple}
    for comp in rustc cargo rust-std-${hostTriple}; do
      test -d "$host_root/$comp"
      cp -a "$host_root/$comp"/. $out/
    done
    tar -xzf ${rustStdAndroidSrc} -C tmp-android
    android_root=tmp-android/rust-std-${version}-${androidTriple}
    test -d "$android_root/rust-std-${androidTriple}"
    cp -a "$android_root/rust-std-${androidTriple}"/. $out/
    chmod -R u+w $out
    test -d $out/lib/rustlib/${androidTriple}/lib
    $out/bin/rustc -V
    $out/bin/rustc --print target-list | grep -qx ${androidTriple}
    runHook postInstall
  '';

  meta = {
    description = "Official Rust toolchain + aarch64-linux-android std for Termux";
    homepage = "https://www.rust-lang.org";
  };
}
