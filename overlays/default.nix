[
    (import ./release-19.03.nix)
    #(import ./ghcjs-asterius-triple.nix)
    #(import ./python.nix)
    (import ./haskell.nix)
    (import ./bootstrap.nix)
    (import ./ghc.nix)
    (import ./ghc-packages.nix)
    (import ./windows.nix)
    # this is currently broken.
    # Let's re-enable once it works.
    # (import ./armv6l-linux.nix)
]