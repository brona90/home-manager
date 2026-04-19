{pkgs, ...}: let
  script = pkgs.writeShellApplication {
    name = "pinentry-emacs-frame";
    runtimeInputs = [pkgs.coreutils];
    # Assuan state variables (cancel, notok, keyinfo, repeat, repeat_err, title)
    # are parsed from the protocol but not all consumed by this wrapper.
    excludeShellChecks = ["SC2034" "SC2318" "SC2015"];
    text =
      builtins.replaceStrings
      ["@emacsclient@"]
      [
        "${pkgs.emacs}/bin/emacsclient"
      ]
      (builtins.readFile ./pinentry-emacs-frame.sh);
  };
in
  pkgs.runCommand "pinentry-emacs-frame-pkg" {
    meta = {
      description = "Pinentry wrapper that routes GPG passphrase prompts to the user's Emacs daemon.";
      mainProgram = "pinentry";
      inherit (pkgs.pinentry-tty.meta) platforms;
    };
  } ''
    mkdir -p $out/bin
    ln -s ${script}/bin/pinentry-emacs-frame $out/bin/pinentry
    ln -s ${script}/bin/pinentry-emacs-frame $out/bin/pinentry-emacs-frame
  ''
