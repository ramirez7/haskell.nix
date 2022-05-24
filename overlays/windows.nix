# Note: We *can not* use a global `lib.optionalAttrs hostPlatform.isWindows`, the
# conditionals need to be in the leafs! If we attach the conditional to the root
# node (e.g. the whole customization here), they will be evaluated at the wrong time
# and not end up with the expected changes we want.
final: prev:
{
   # on windows we have this habit of putting libraries
   # into `bin`, whereas on unix it's usually `lib`. For
   # this confuses nix easily. So we'll just move the
   # .dll's from `bin` into `$out/lib`. Such that they
   # are trivially found.
  #  openssl = prev.openssl.overrideAttrs (drv: {
  #   #  postInstall = with prev.stdenv; drv.postInstall + lib.optionalString hostPlatform.isWindows ''
  #   #    cp $bin/bin/*.dll $out/lib/
  #   #  '';
  #   postFixup = "";
  #  });
} // prev.lib.optionalAttrs (prev ? mfpr) {
   mfpr = if !prev.stdenv.hostPlatform.isWindows then prev.mpfr else prev.mfpr.overrideAttrs (drv: {
     configureFlags = (drv.configureFlags or []) ++ [ "--enable-static --disable-shared" ];
   });
} // {
   libmpc = if !prev.stdenv.hostPlatform.isWindows then prev.libmpc else prev.libmpc.overrideAttrs (drv: {
     configureFlags = (drv.configureFlags or []) ++ [ "--enable-static --disable-shared" ];
   });

   binutils-unwrapped = prev.binutils-unwrapped.overrideAttrs (attrs: {
     patches = attrs.patches ++ final.lib.optional (final.stdenv.targetPlatform.isWindows && attrs.version or "" == "2.31.1") (
       final.fetchpatch {
         name = "plugin-target-handling-patch";
         url = "https://sourceware.org/git/?p=binutils-gdb.git;a=patch;h=999d6dff80fab12d22c2a8d91923db6bde7fb3e5";
         excludes = ["bfd/ChangeLog"];
         sha256 = "0a60w52wrf6qzchsiviprmcblq0q1fv1rbkx4gkk482dmvx4j0l6";
       }
     );
   });

   haskell-nix = prev.haskell-nix // ({
     defaultModules = prev.haskell-nix.defaultModules ++ [
      ({ pkgs, buildModules, config, lib, ... }:
      let
        withTH = import ./mingw_w64.nix {
          inherit (pkgs.stdenv) hostPlatform;
          inherit (pkgs) stdenv lib writeScriptBin;
          wine = pkgs.buildPackages.winePackages.minimal;
          inherit (pkgs.windows) mingw_w64_pthreads;
          inherit (pkgs) gmp;
          inherit (pkgs) buildPackages;
          inherit (pkgs) windows;
          inherit (pkgs.buildPackages) symlinkJoin;
          # iserv-proxy needs to come from the buildPackages, as it needs to run on the
          # build host.
          inherit (final.buildPackages.ghc-extra-packages."${config.compiler.nix-name}".iserv-proxy.components.exes) iserv-proxy;
          # remote-iserv however needs to come from the regular packages as it has to
          # run on the target host.
          inherit (final.ghc-extra-packages."${config.compiler.nix-name}".remote-iserv.components.exes) remote-iserv;
          # we need to use openssl.bin here, because the .dll's are in the .bin expression.
          # extra-test-libs = [ pkgs.rocksdb pkgs.openssl.bin pkgs.libffi pkgs.gmp ];
        } // {
          # we can perform testing of cross compiled test-suites by using wine.
          # Therefore let's enable doCrossCheck here!
          doCrossCheck = pkgs.stdenv.hostPlatform.isWindows;
        };
      in {
        packages = {

          # Apply https://github.com/haskell/cabal/pull/6055
          # See also https://github.com/input-output-hk/iohk-nix/issues/136
          # Cabal.patches = [ ({ version, revision }: (if builtins.compareVersions version "3.0.0" < 0
          #   then pkgs.fetchpatch {
          #     url = "https://patch-diff.githubusercontent.com/raw/haskell/cabal/pull/6055.diff";
          #     sha256 = "145g7s3z9q8d18pxgyngvixgsm6gmwh1rgkzkhacy4krqiq0qyvx";
          #     stripLen = 1;
          #   }
          #   else null)) ];

          # clock 0.7.2 needs to be patched to support cross compilation.
          clock.patches              = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ({ version, revision }: (if version == "0.7.2" then ./patches/clock-0.7.2.patch else null)) ];
          # nix calls this package crypto
          cryptonite-openssl.patches = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ({ version, revision }: if version == "0.7" then ./patches/cryptonite-openssl-0.7.patch else null) ];

          # this patch seems to be rather flaky and highly dependent on
          # the network library. I think we might need to respin that in
          # a better way that doesn't just delete some code, but makes
          # the bounds checks stricter.
          # http-client.patches        = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ({ version, revision }: if version == "0.5.14" then ./patches/http-client-0.5.14.patch else null) ];

          conduit.patches            = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ({ version, revision }: if builtins.compareVersions version "1.3.1.1" < 0 then ./patches/conduit-1.3.0.2.patch else null) ];
          streaming-commons.patches  = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ./patches/streaming-commons-0.2.0.0.patch ];
          x509-system.patches        = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isWindows [ ./patches/x509-system-1.6.6.patch ];

          # Set all of these to [], as these form the
          # dependency graph of the libiserv, iserv-proxy, and iserv-remote
          # packages.  Subsequently we do not want the defaults that `withTH`
          # `-fexternal-interpreter` would install here.  That would ultimately
          # result in cyclic dependencies as it injects `remote-iserv` and
          # `iserv-proxy` as a dependency into every package.
          bytestring.setupBuildFlags = [];
          containers.setupBuildFlags = [];
          binary.setupBuildFlags = [];
          filepath.setupBuildFlags = [];
          time.setupBuildFlags = [];
          Win32.setupBuildFlags = [];
          libiserv.setupBuildFlags = [];
          remote-iserv.setupBuildFlags = [];
          directory.setupBuildFlags = [];
          ghc-boot.setupBuildFlags = [];
          transformers.setupBuildFlags = [];
          ghci.setupBuildFlags = [];
          network.setupBuildFlags = [];
          unix.setupBuildFlags = [];

          # Newer Win32 includes hsc2hs, but we can get that that from the ghc derivation and
          # if the cabal plan included hsc2hs it winds up trying to build a windows version.
          Win32.components.library.build-tools = pkgs.lib.mkForce [];
        }
        # Fix dependencies and case-sensitive filesystem builds for unix-time.
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isWindows {
          unix-time.components.library.libs = [ pkgs.windows.mingw_w64_pthreads ];
          unix-time.postUnpack = "substituteInPlace */cbits/win_patch.h --replace Windows.h windows.h";
        };
      } // withTH
      )
    ];
  });
}
