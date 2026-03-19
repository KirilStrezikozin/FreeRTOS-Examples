{
  description = "Flake for the Microcontrollers class";

  inputs = {
    # NixOS official package source, using the nixos-24.11 branch here.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    systems.url = "github:nix-systems/default-linux";
  };

  outputs = {
    self,
    nixpkgs,
    systems,
    ...
  }: let
    # Desired version of Pico-SDK, Pico-extras, and Picotool.
    toolchainVersion = "2.2.0";

    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs (import systems);

    pkgsFor = eachSystem (system:
      import nixpkgs {
        localSystem = system;
        overlays = with self.overlays; [
          pico-overlays
        ];
      });

    mkConfigurePicoEnv = system:
      with pkgsFor.${system}; ''
        export PICO_SDK_PATH=${pico-sdk-overlay}/lib/pico-sdk
        export PICO_EXTRAS_PATH=${pico-extras-overlay}/lib/pico-extras
      '';

    formatterInputs = system:
      with pkgsFor.${system}; [
        deadnix
        statix
        alejandra
        llvmPackages_19.clang-tools
        shellcheck
        fd
      ];

    # Get CMake build directory name. Default is "build".
    # Usage: `CMAKE_BUILD_DIR=build nix build --impure`.
    buildDir = let
      v = builtins.getEnv "CMAKE_BUILD_DIR";
    in
      if v == ""
      then "build"
      else v;
  in {
    overlays = import ./nix/overlays.nix {inherit self lib nixpkgs buildDir toolchainVersion;};

    devShells = eachSystem (system: rec {
      default = develop;

      develop = pkgsFor.${system}.mkShell {
        packages = with pkgsFor.${system};
          [
            tio # Terminal program to interface with serial.
            udisks # Interact with bootloader file-system.

            gcc-arm-embedded-13
            cmake
            ninja
            python3 # Build requirements for pico-sdk.
            libusb1 # Required for picotool.

            pico-sdk-overlay
            pico-extras-overlay
            picotool-overlay

            # Developer utilities.
            typst # Logbook
            cmake-language-server # CMake lsp.
            tinymist # Typst lsp.
            websocat # Typst lsp dep.
            nixd # Nix lsp.
          ]
          ++ formatterInputs system;

        shellHook = mkConfigurePicoEnv system;
      };
    });

    # Format project code and check for styling rules using the `nix fmt`
    # command. Shell scripts are not formatted but checked only. Examples:
    #   1. Format all C/C++, Nix, and shell script code:
    #        nix fmt .
    #   2. Check C/C++ code only and do not perform formatting in place:
    #        nix fmt . -- --c-cxx-format -- --dry-run --Werror
    #   3. Exclude all files in the build directory from checks. Note that this
    #      is not necessary if build directory is in the .gitignore file:
    #        nix fmt . -- -E build
    formatter = eachSystem (
      system:
        pkgsFor.${system}.callPackage
        ./nix/formatter.nix {
          inherit formatterInputs;
        }
    );
  };
}
