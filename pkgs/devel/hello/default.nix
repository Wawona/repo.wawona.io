{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "hello";
  version = "2.12";

  src = pkgs.fetchurl {
    url = "mirror://gnu/hello/hello-${version}.tar.gz";
    sha256 = "cf04af86dc085268c5f4470fbae49b18afbc221b78096aab842d934a76bad0ab";
  };

  sileo = {
    package = "com.aspauldingcode.hello";
    architecture = "iphoneos-arm64";
    description = "Rootless Hello";
    maintainers = [ "aspauldingcode" ];
  };

  meta = {
    description = "A friendly greeting program";
    homepage = "https://repo.wawona.io";
  };
}
