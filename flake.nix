{
  description = "p2pool-anywhere - Deploy P2Pool (v2) anywhere with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    p2poolv2.url = "github:p2poolv2/p2poolv2/v0.18.0";
  };

  outputs =
    { self, nixpkgs, p2poolv2, ... }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin" # TODO: Remove x86_64-darwin?
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ self.overlays.testnet5 ];
            }
          )
        );
    in
    {
      # testnet5 overlay: adds package `bitcoind-testnet5`
      overlays.testnet5 = final: prev: {
        bitcoind-testnet5 = prev.bitcoind.overrideAttrs (old: {
          pname = "bitcoind-testnet5";
          version = "32.1-unstable-2026-11-14";

          # Head of https://github.com/bitcoin/bitcoin/pull/35861 (includes the Testnet5 genesis block).
          # fetchgit rather than fetchFromGitHub: the repo uses export-subst, so GitHub
          # tarballs are not byte-identical to the git tree.
          src = final.fetchgit {
            url = "https://github.com/bitcoin/bitcoin.git";
            rev = "ee505609676a10c389da5962b25a2c0080b9df57";
            hash = "sha256-pIkVK8/TEuNkez+NpgAo88JV9AOiAvbDwgC88Jm1oLE=";
          };

          # Nixpkgs checks the GPG-signed SHA256SUMS of the release tarball here,
          # which doesn't apply to a git checkout.
          preUnpack = "";

          # versionCheckHook looks for `version` in `bitcoin-cli --version`,
          # but the PR source still reports v32.1.0.
          doInstallCheck = false;
        });
      };

      packages = forAllSystems (pkgs:
      let
        upstream = p2poolv2.packages.${pkgs.stdenv.hostPlatform.system}.p2poolv2_node;

        # Upstream's package only installs the binaries. Wrap upstream (no rebuild needed) to include the dashboard
        # assets from the p2poolv2 input and set `P2POOL_STATIC_DIR` to point at them.
        p2poolv2_node = pkgs.symlinkJoin {
          name = "p2poolv2_node-${upstream.version}";
          inherit (upstream) version;
          paths = [ upstream ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            mkdir -p $out/share/p2poolv2
            cp -r ${p2poolv2}/p2poolv2_api/static $out/share/p2poolv2/static
            # --set-default: a user-supplied P2POOL_STATIC_DIR still wins
            wrapProgram $out/bin/p2poolv2 \
              --set-default P2POOL_STATIC_DIR $out/share/p2poolv2/static
          '';
          passthru.unwrapped = upstream;
          meta = (upstream.meta or { }) // {
            mainProgram = "p2poolv2";
          };
        };
      in
      {
        # default package is P2Poolv2
        default = p2poolv2_node;
        inherit p2poolv2_node;
        # bitcoind-testnet5 from the testnet5 overlay
        inherit (pkgs) bitcoind-testnet5;
      });
    };
}
