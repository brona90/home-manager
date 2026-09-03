# The Ollama server, as a pinned vendor release bundle.
#
# WHY NOT pkgs.ollama / pkgs.ollama-cuda -- this is the load-bearing decision in
# this module, so it is written down rather than left to be rediscovered.
#
# Three candidates were measured on the box this runs on (WSL2 Debian 12, RTX
# 3090, driver libs at /usr/lib/wsl/lib):
#
#   pkgs.ollama (CPU)   `nix build --dry-run`: FETCHED, 23.41 MiB. Cheap --
#                       and useless. It builds with acceleration=null, so every
#                       model runs on the CPU. Measured on this machine with a
#                       per-request num_gpu:0 against the live server:
#                         qwen2.5:7b  GPU 83.4 tok/s   CPU 0.3 tok/s
#                       That is a 278x regression on the model capture_local.py
#                       drives, whose own read timeout is 300s. The SessionEnd
#                       capture would never again finish. Ruled out by
#                       measurement, not by taste.
#
#   pkgs.ollama-cuda    `nix build --dry-run`: must BUILD. The plan pulls in
#                       cuda_nvcc 12.9, libcublas 12.9, cuda_cudart, gcc-14 and
#                       the ollama go-modules -- none of it substitutable from
#                       cache.nixos.org. The entire point of this branch is a
#                       WSL instance that can be thrown away and rebuilt; a
#                       rebuild that must compile a CUDA toolchain before the
#                       machine can remember anything is not that. It also still
#                       needs the libcuda.so.1 workaround below, because
#                       addDriverRunpath points at /run/opengl-driver/lib, which
#                       does not exist on Debian.
#
#   this file           FETCHED, 1.4 GiB, zero compilation (2m16s measured on
#                       this connection). Ships its own cuda_v12/cuda_v13 ggml
#                       runners, so the only thing it needs from outside the
#                       store is libcuda.so.1 -- which WSL guarantees at
#                       /usr/lib/wsl/lib. Same binary the box already runs, so
#                       `hms` changes no model behaviour.
#
# The cost of this choice is honest and worth stating: a ~4 GiB store path, and
# `version` + `hash` below are bumped by hand rather than by `nfu`. That is the
# price of not compiling CUDA on every rebuild. If that trade ever stops being
# worth it, `my.ollama.package = pkgs.ollama-cuda;` is the whole migration --
# the unit in default.nix already exports the LD_LIBRARY_PATH it would need.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zstd,
  vulkan-loader,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "ollama-bin";
  version = "0.33.2";

  src = fetchurl {
    url = "https://github.com/ollama/ollama/releases/download/v${finalAttrs.version}/ollama-linux-amd64.tar.zst";
    hash = "sha256-l4UkfeomTZBy8J9snA60uOZmiSgmo9g4jro+j7ntHbk=";
  };

  nativeBuildInputs = [autoPatchelfHook zstd];
  # The prebuilt runners are C++; the CUDA halves of the bundle resolve against
  # each other inside the output. vulkan-loader is here only because the bundle
  # also ships a libggml-vulkan.so linked against libvulkan.so.1 -- satisfying
  # the link properly is cheaper than adding a third entry to the ignore list,
  # and an ignored NEEDED entry gets no RPATH at all, so the runner could never
  # load even where a Vulkan ICD does exist.
  buildInputs = [stdenv.cc.cc.lib vulkan-loader];

  # The bundle is a bare `bin/` + `lib/` pair with NO top-level directory, so
  # the default unpackPhase has no single source root to cd into and aborts.
  # Verified with `tar -t`: exactly two entries, bin/ollama and lib/ollama.
  unpackPhase = ''
    runHook preUnpack
    mkdir -p "$NIX_BUILD_TOP/bundle"
    cd "$NIX_BUILD_TOP/bundle"
    zstd -dc "$src" | tar -x
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  # libcuda.so.1 and libnvidia-ml.so.1 are DRIVER libraries. They are not in
  # nixpkgs and must not be: the kernel driver and its userspace half have to
  # match, so the only correct copy is the one the host provides. autoPatchelf
  # would otherwise fail the build outright for a dependency that is supposed
  # to be resolved at runtime -- see my.ollama.driverLibraryPath, which puts
  # /usr/lib/wsl/lib on the server unit's LD_LIBRARY_PATH.
  autoPatchelfIgnoreMissingDeps = [
    "libcuda.so.1"
    "libnvidia-ml.so.1"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r bin "$out/bin"
    cp -r lib "$out/lib"
    chmod -R u+w "$out"
    runHook postInstall
  '';

  # `ollama serve` finds its ggml/CUDA runners relative to its own argv[0] via
  # /proc/self/exe, so $out/bin and $out/lib must stay siblings. Do not "tidy"
  # this into a wrapper that moves the binary.
  meta = {
    description = "Ollama model server (pinned upstream Linux bundle, GPU runners included)";
    homepage = "https://github.com/ollama/ollama";
    # Ollama itself is MIT; the bundled CUDA runtime is NVIDIA-redistributable,
    # which is why this needs the flake's existing allowUnfree.
    license = with lib.licenses; [mit unfreeRedistributable];
    platforms = ["x86_64-linux"];
    mainProgram = "ollama";
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
  };
})
