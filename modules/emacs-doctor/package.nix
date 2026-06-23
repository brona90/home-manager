{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "emacs-doctor";
  version = "0.1.0";

  src = ./src;

  # No Go module dependencies (stdlib only), so there is nothing to vendor;
  # null is the correct permanent value, not a placeholder.
  vendorHash = null;

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=0.1.0"
  ];

  # Unit tests (pure parsers/classifiers) run in the derivation.
  doCheck = true;

  meta = {
    description = "Emacs daemon health/recovery + WSL diagnostics CLI";
    mainProgram = "emacs-doctor";
    license = lib.licenses.mit;
    # Linux-only: relies on systemd user units, /proc, and WSLg specifics.
    platforms = lib.platforms.linux;
  };
}
