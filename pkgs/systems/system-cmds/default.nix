{ pkgs, mkWawonaPackage, libiosexec, target ? "ios" }:

let
  prefix = if target == "android" then "/data/data/com.termux/files/usr" else "/var/jb";
in
mkWawonaPackage rec {
  pname = "system-cmds";
  version = "950";

  src = pkgs.fetchurl {
    url = "https://github.com/apple-oss-distributions/system_cmds/archive/refs/tags/system_cmds-${version}.tar.gz";
    sha256 = "1405fs99vaaznspc1kvqmjcnz7v1gki8sz54ipdl16ajxgyabqpn";
  };

  patches = [
    ./patches/0001-system_cmds-shutdown-may-not-work.patch
    ./patches/0002-Add-missing-int-reboot3-int-declaration.patch
    ./patches/bettercrypt.diff
    ./patches/fix-pwd_mkdb-comment-handling.diff
  ];

  buildInputs = with pkgs; [ openpam ncurses ] ++ [ libiosexec ] ++ (lib.optional (target == "android") libxcrypt);

  preConfigure = ''
    sed -i '/#include <stdio.h>/a #include <crypt.h>' login.tproj/login.c
    sed -i '1 i\#include <libiosexec.h>' login.tproj/login.c
    sed -i '1 i\#define IOPOL_TYPE_VFS_HFS_CASE_SENSITIVITY 1\n#define IOPOL_SCOPE_PROCESS 0\n#define IOPOL_VFS_HFS_CASE_SENSITIVITY_DEFAULT 0\n#define IOPOL_VFS_HFS_CASE_SENSITIVITY_FORCE_CASE_SENSITIVE 1\n#define PRIO_DARWIN_ROLE_UI 0x2' taskpolicy.tproj/taskpolicy.c
    sed -i -E -e 's|/usr|${prefix}/usr|g' -e 's|/sbin|${prefix}/sbin|g' \
      shutdown.tproj/pathnames.h getty.tproj/{ttys,gettytab}.5 sc_usage.tproj/sc_usage.{1,c} at.tproj/{at.1,pathnames.h}
    sed -i 's|/etc|${prefix}/etc|' passwd.tproj/{file_,}passwd.c
    sed -i 's|#include <mach/i386/vm_param.h>|#include <mach/vm_param.h>|' memory_pressure.tproj/memory_pressure.c
    sed -i 's|/System/Library/Kernels/kernel.development|${prefix}/Library/Kernels/kernel.development|' latency.tproj/latency.{1,c}
  '';

  buildPhase = ''
    # Compile gperf files
    for gperf in getconf.tproj/*.gperf; do
      LC_ALL=C awk -f getconf.tproj/fake-gperf.awk < $gperf > getconf.tproj/"$(basename $gperf .gperf).c"
    done

    rm -f passwd.tproj/{od,nis}_passwd.c

    # Compile wait4path
    $CC $CFLAGS $LDFLAGS -o wait4path.x wait4path/*.c

    # Compile all the tproj projects
    for tproj in ac accton arch at atrun cpuctl dmesg dynamic_pager fs_usage getconf getty hostinfo iostat latency login lskq memory_pressure mkfile newgrp purge pwd_mkdb reboot shutdown stackshot trace passwd sync sysctl vifs vipw zdump zic nologin taskpolicy lsmp sc_usage ltop; do
      echo "Building $tproj"
      TARGET_CFLAGS=""
      TARGET_LDFLAGS=""
      case $tproj in
        arch) TARGET_LDFLAGS="-framework CoreFoundation -framework Foundation -lobjc";;
        login) TARGET_CFLAGS="-DUSE_PAM=1"; TARGET_LDFLAGS="-lpam -liosexec";;
        dynamic_pager) TARGET_CFLAGS="-Idynamic_pager.tproj";;
        pwd_mkdb) TARGET_CFLAGS="-D_PW_NAME_LEN=MAXLOGNAME -D_PW_YPTOKEN=__YP!";;
        passwd) TARGET_CFLAGS="-DINFO_PAM=4"; TARGET_LDFLAGS="-lcrypt -lpam";;
        shutdown) TARGET_LDFLAGS="-lbsm -liosexec";;
        sc_usage) TARGET_LDFLAGS="-lncurses";;
        at) TARGET_LDFLAGS="-Iat.tproj -DPERM_PATH=${prefix}/usr/lib/cron -DDAEMON_UID=1 -DDAEMON_GID=1 -D__FreeBSD__ -DDEFAULT_AT_QUEUE='a' -DDEFAULT_BATCH_QUEUE='b'";;
        fs_usage) TARGET_LDFLAGS="-Wno-error-implicit-function-declaration";; 
        latency) TARGET_LDFLAGS="-lncurses -lutil";;
        trace) TARGET_LDFLAGS="-lutil";;
        lskq) TARGET_LDFLAGS="-Ilskq.tproj -DEVFILT_NW_CHANNEL=(-16)";;
        zic) TARGET_CFLAGS='-DUNIDEF_MOVE_LOCALTIME -DTZDIR="/var/db/timezone/zoneinfo" -DTZDEFAULT="/var/db/timezone/localtime"';;
      esac
      $CC $CFLAGS -D__kernel_ptr_semantics="" -Iinclude -o $tproj $tproj.tproj/*.c -D'__FBSDID(x)=' $TARGET_CFLAGS $LDFLAGS $TARGET_LDFLAGS -framework CoreFoundation -framework IOKit -DPRIVATE -D__APPLE_PRIVATE
    done
  '';

  installPhase = ''
    mkdir -p $out${prefix}/Library/LaunchDaemons $out${prefix}/etc/pam.d $out${prefix}/bin $out${prefix}/sbin $out${prefix}/usr/bin $out${prefix}/usr/sbin $out${prefix}/usr/libexec $out${prefix}/usr/share/man/man{1,5,8}

    sed 's|/usr|${prefix}/usr|' < atrun.tproj/com.apple.atrun.plist > $out${prefix}/Library/LaunchDaemons/com.apple.atrun.plist

    install -m755 pagesize.tproj/pagesize.sh $out${prefix}/usr/bin/pagesize
    install -m755 wait4path.x $out${prefix}/bin/wait4path

    cp -a dmesg dynamic_pager nologin reboot shutdown $out${prefix}/sbin
    cp -a sync $out${prefix}/bin

    cp -a ac accton iostat mkfile pwd_mkdb sysctl taskpolicy vifs vipw zdump zic $out${prefix}/usr/sbin
    cp -a arch at cpuctl fs_usage getconf hostinfo latency login lskq lsmp ltop memory_pressure newgrp passwd purge sc_usage stackshot trace $out${prefix}/usr/bin
    cp -a atrun getty $out${prefix}/usr/libexec

    # man pages
    cp -a {arch,at,fs_usage,getconf,latency,login,lskq,lsmp,ltop,memory_pressure,newgrp,pagesize,passwd,trace,vm_stat,zprint}.tproj/*.1 wait4path/*.1 $out${prefix}/usr/share/man/man1
    cp -a {getty,nologin,sysctl}.tproj/*.5 $out${prefix}/usr/share/man/man5
    cp -a {ac,accton,atrun,cpuctl,dmesg,dynamic_pager,getty,hostinfo,iostat,mkfile,nologin,nvram,purge,pwd_mkdb,reboot,sa,shutdown,sync,sysctl,taskpolicy,vifs,vipw,zdump,zic}.tproj/*.8 $out${prefix}/usr/share/man/man8

    ln -s $out${prefix}/usr/bin/arch $out${prefix}/usr/bin/machine
    ln -s $out${prefix}/sbin/reboot $out${prefix}/sbin/halt
  '';

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
