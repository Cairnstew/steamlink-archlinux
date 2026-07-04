{
  description = "Steam Link Arch Linux boot medium creator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.stdenv.mkDerivation {
            name = "steamlink-archlinux";
            src = ./.;

            dontBuild = true;

            installPhase = ''
              mkdir -p $out/share/steamlink-archlinux
              cp -r ./. $out/share/steamlink-archlinux/
              rm -rf $out/share/steamlink-archlinux/.git \
                     $out/share/steamlink-archlinux/flake.nix \
                     $out/share/steamlink-archlinux/flake.lock

              mkdir -p $out/bin
              cat > $out/bin/steamlink-archlinux << WRAPPER
#!${pkgs.bash}/bin/bash
exec ${pkgs.bash}/bin/bash "\$(dirname "\$(readlink -f "\$0")")/../share/steamlink-archlinux/boot_disk_creator.sh"
WRAPPER
              chmod +x $out/bin/steamlink-archlinux
            '';

            meta = with pkgs.lib; {
              description = "Create a bootable Arch Linux USB drive for the Valve Steam Link";
              homepage = "https://github.com/craw0967/steamlink-archlinux";
              license = licenses.gpl2Only;
              maintainers = [];
              platforms = platforms.linux;
            };
          };
        });

      apps = forAllSystems (system:
        let
          pkg = self.packages.${system}.default;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/steamlink-archlinux";
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ curl gnused gnutar ];
          };
        });
    };
}
