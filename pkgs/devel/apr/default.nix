{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "apr";
  version = "1.7.0";
  src = pkgs.fetchurl {
    url = "https://archive.apache.org/dist/apr/apr-1.7.0.tar.gz";
    sha256 = "18nmqbj9bl6fgjbw1hfbzagh8qvxrxngp7r5j6scgzg3bbsdpsa8";
  };
  nativeBuildInputs = [ pkgs.buildPackages.clang ];
  postConfigure = ''
    sed -i 's|#error Can not determine the proper size for pid_t|typedef int apr_pid_t;|g' include/apr.h
    sed -i 's|struct iovec|/*struct iovec|g' include/apr_want.h
    sed -i 's|};|};*/|g' include/apr_want.h
    sed -i 's|msg = strerror_r(statcode, buf, bufsize);|strerror_r(statcode, buf, bufsize); msg = buf;|g' misc/unix/errorcodes.c
  '';

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
