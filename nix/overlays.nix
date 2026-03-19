{
  self,
  lib,
  ...
}: {
  pico-overlays = lib.composeManyExtensions [
    self.overlays.pico-sdk
    self.overlays.pico-extras
    self.overlays.picotool
  ];

  pico-sdk = final: _prev: {
    pico-sdk-overlay = final.stdenv.mkDerivation {
      pname = "pico-sdk";
      version = "2.2.0";

      src = builtins.fetchGit {
        url = "https://github.com/raspberrypi/pico-sdk";
        rev = "a1438dff1d38bd9c65dbd693f0e5db4b9ae91779";
        submodules = true;
      };

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/pico-sdk
        cp -r ./* $out/lib/pico-sdk
        runHook postInstall
      '';

      meta = with lib; {
        homepage = "https://github.com/raspberrypi/pico-sdk";
        description = "SDK provides the headers, libraries and build system necessary to write programs for the RP2040-based devices";
        license = licenses.bsd3;
        maintainers = with maintainers; [muscaln];
        platforms = platforms.unix;
      };
    };
  };

  pico-extras = final: _prev: {
    pico-extras-overlay = final.stdenv.mkDerivation {
      pname = "pico-extras";
      version = "2.2.0";

      src = builtins.fetchGit {
        url = "https://github.com/raspberrypi/pico-extras";
        rev = "82409a94de00802105c84e5c06f333114bb8b316";
      };

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/pico-extras
        cp -r ./* $out/lib/pico-extras
        runHook postInstall
      '';

      meta = with lib; {
        homepage = url;
        description = "Additional libraries for Pico SDK";
        license = licenses.bsd3;
        platforms = platforms.unix;
      };
    };
  };

  picotool = final: prev: {
    picotool-overlay =
      (prev.picotool.override {
        pico-sdk = final.pico-sdk-overlay;
      })
      .overrideAttrs {
        version = "2.2.0";

        src = builtins.fetchGit {
          url = "https://github.com/raspberrypi/picotool";
          rev = "a7eb3988f0645239185fadb4e25d8279478c2dbb";
        };

        postInstall = ''
          install -Dm444 ../udev/60-picotool.rules -t $out/etc/udev/rules.d
        '';
      };
  };
}
