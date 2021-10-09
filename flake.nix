{
  description = "EKS Experiment";

  inputs.utils.url = "github:numtide/flake-utils";

  outputs = { self, utils, nixpkgs }:
    utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      {
        packages.calicoctl = pkgs.stdenv.mkDerivation {
          name = "calicoctl";
          src = pkgs.fetchurl {
            url = "https://github.com/projectcalico/calicoctl/releases/download/v3.16.0/calicoctl";
            sha256 = "14qv4wv8ndz9g7v2bq8w1fgzw14dfhn5byzp5jqp6q26z9vp0qx7";
          };
          dontUnpack = true;
          dontBuild = true;
          installPhase = ''
            cp $src calicoctl
            install -Dm0755 calicoctl -t $out/bin
          '';
        };
        devShell = with pkgs; mkShell {
          nativeBuildInputs = [
            self.packages.${system}.calicoctl
            bashInteractive
            mkcert
            kubectl
            kubelogin-oidc
            terraform
          ];
        };
      });
}

