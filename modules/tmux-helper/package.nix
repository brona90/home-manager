{
  lib,
  buildGoModule,
  stdenv,
  darwin,
}:
buildGoModule rec {
  pname = "tmux-helper";
  version = "0.1.0";

  src = ./src;

  # Filled in after first build attempt prints the real hash.
  vendorHash = null;

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  # Keep tests in the derivation (Phase 1 only has version+stubs; later phases add real tests).
  doCheck = true;

  # Ad-hoc codesign on darwin so BeyondTrust EPM can fingerprint by stable cdhash + identifier.
  postInstall = lib.optionalString stdenv.isDarwin ''
    ${darwin.sigtool}/bin/codesign --force --sign - --options runtime       --identifier com.brona.tmux-helper       $out/bin/tmux-helper
  '';

  meta = {
    description = "One-shot Go helper for Nix-managed tmux config";
    mainProgram = "tmux-helper";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
