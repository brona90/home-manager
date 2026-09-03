# Ollama, declared.
#
# Until this module existed, Ollama was the largest undeclared dependency in the
# estate: /usr/local/bin/ollama, owned by NO dpkg package (verified with
# `dpkg -S`), installed by the vendor's curl|sh script, started by a hand-rolled
# /etc/systemd/system/ollama.service, serving four models pulled by hand. Qdrant
# and SearXNG are declared and come back after a `wsl --unregister`; Ollama did
# not. The knowledge graph would return with its entities intact and recall
# nothing, because nothing could produce a query vector.
#
# See package.nix for why this is the vendor bundle rather than pkgs.ollama.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.ollama;

  pullModels = pkgs.writeShellApplication {
    name = "ollama-pull-models";
    runtimeInputs = [cfg.package pkgs.curl pkgs.coreutils];
    text = ''
      url="http://${cfg.host}:${toString cfg.port}"
      # `ollama serve` binds a moment after its unit reaches "exec", so poll
      # rather than assume -- but bound the wait, so a server that never comes
      # up fails this unit loudly instead of hanging every boot forever.
      ready=0
      for _ in $(seq 1 ${toString cfg.startupWait}); do
        if curl -sf --max-time 2 "$url/api/version" >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 1
      done
      if [ "$ready" -ne 1 ]; then
        echo "ollama-pull-models: $url did not answer within ${toString cfg.startupWait}s; not pulling." >&2
        exit 1
      fi

      # An array, not a bare word list: with a single-element my.ollama.models
      # (the default) `for model in nomic-embed-text` is SC2043, and
      # writeShellApplication runs shellcheck at BUILD time, so that is a build
      # failure rather than a lint nit. The array is also the correct quoting
      # for a model name containing a slash, e.g. MFDoom/deepseek-coder-v2.
      models=(${lib.escapeShellArgs cfg.models})
      rc=0
      for model in "''${models[@]}"; do
        # `ollama pull` is idempotent -- an already-current model costs a
        # manifest check, not a re-download -- so this is safe on every boot.
        echo "ollama-pull-models: ensuring $model"
        ollama pull "$model" || rc=$?
      done
      exit "$rc"
    '';
  };
in {
  options.my.ollama = {
    enable = lib.mkEnableOption "the Ollama model server (claude-kg's embedder and local capture model)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {};
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix {}";
      description = ''
        The Ollama build to run. Swap in `pkgs.ollama-cuda` to trade a 1.4 GiB
        fetch for a local CUDA compile; see package.nix for the measurements
        behind the default.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the server binds. Loopback on purpose: this box is reachable
        from the LAN and through a Cloudflare tunnel, and an Ollama with no
        authentication must not be either.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port the server binds. claude-kg's OLLAMA_URL default must agree with this.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/ollama/models";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.local/share/ollama/models"'';
      description = ''
        Where model blobs live. Under $HOME rather than the vendor's
        /usr/share/ollama, because this is a systemd USER unit: home-manager
        cannot write /etc/systemd/system, and a user-owned store is what makes
        the models survive as ordinary user data.

        MIGRATION: the existing 15 GiB vendor store is at
        /usr/share/ollama/.ollama/models, owned by the `ollama` system user and
        not writable by gfoster. Either let this re-pull (my.ollama.models is
        pulled automatically; the rest on demand), or hand the old store over
        with `sudo chown -R gfoster:gfoster /usr/share/ollama/.ollama` and point
        this option at it. Both are one-time root actions and neither is done
        by activation.
      '';
    };

    driverLibraryPath = lib.mkOption {
      type = lib.types.str;
      default = "/usr/lib/wsl/lib";
      description = ''
        Directory holding the host's GPU driver libraries (libcuda.so.1). Not a
        nix store path and it cannot be one: the userspace driver has to match
        the kernel one, so it comes from the host. WSL2 publishes it here;
        package.nix correspondingly ignores libcuda.so.1 at autoPatchelf time.
        Set to "" on a machine with no GPU -- the bundle falls back to its CPU
        runners.
      '';
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["nomic-embed-text"];
      description = ''
        Models guaranteed present. Defaults to just the embedder, because that
        is the one the recall path cannot degrade without: a graph full of
        entities and no way to embed a query returns nothing. The capture model
        (qwen2.5:7b, 4.7 GiB) is deliberately NOT here -- it is pulled on demand
        and its absence costs a capture, not every prompt.
      '';
    };

    startupWait = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Seconds ollama-models waits for the server to answer /api/version before giving up.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];

    # The server writes here; create it before the unit needs it.
    home.activation.ollamaModelsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.coreutils}/bin/mkdir -p "${cfg.modelsDir}"
    '';

    # systemd.user is Linux-only -- home-manager errors if this is set on a
    # non-Linux host. Gate it the way claude-kg and searxng gate theirs.
    systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      services.ollama = {
        Unit = {
          Description = "Ollama model server (claude-kg embedder + local capture model)";
          After = ["network-online.target"];
        };
        Service = {
          Type = "exec";
          ExecStart = "${cfg.package}/bin/ollama serve";
          Restart = "always";
          RestartSec = 3;

          # The PATH here is EXPLICIT and store-only, and that is the point.
          # The hand-rolled unit this replaces was generated by the vendor
          # script from whatever interactive shell happened to run it, and had
          # frozen a snapshot of that shell's PATH: 65 entries, of which 29 no
          # longer existed -- the whole mise install tree, /Docker/host/bin, and
          # /mnt/c/Users/brona/.local/share/mise/bin. Every one of those is a
          # 9P round trip or a failed stat on each lookup, and none of them was
          # ever needed: `ollama serve` execs nothing but its own runners.
          #
          # LD_LIBRARY_PATH, by contrast, is load-bearing: it is how the
          # bundled CUDA runners find the host's libcuda.so.1, which is
          # deliberately absent from the store (see package.nix).
          Environment =
            [
              "PATH=${lib.makeBinPath [cfg.package pkgs.coreutils]}"
              "HOME=${config.home.homeDirectory}"
              "OLLAMA_HOST=${cfg.host}:${toString cfg.port}"
              "OLLAMA_MODELS=${cfg.modelsDir}"
            ]
            ++ lib.optional (cfg.driverLibraryPath != "")
            "LD_LIBRARY_PATH=${cfg.driverLibraryPath}";
        };
        Install.WantedBy = ["default.target"];
      };

      # Model provisioning as its own oneshot rather than an activation script.
      # An activation script would have to pull while the server is still the
      # OLD generation's (or not running at all -- home-manager starts changed
      # units AFTER activation), and would block `hms` on a 274 MiB download.
      # As a unit ordered after ollama.service it runs when the server is
      # genuinely up, on boot and after a switch, and its failures land in the
      # journal where they can be read.
      services.ollama-models = {
        Unit = {
          Description = "Ensure the models claude-kg depends on are present";
          After = ["ollama.service"];
          Requires = ["ollama.service"];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = ["OLLAMA_HOST=${cfg.host}:${toString cfg.port}"];
          ExecStart = "${pullModels}/bin/ollama-pull-models";
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
