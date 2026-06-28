{
  config,
  lib,
  ...
}: let
  cfg = config.my.claudeSpecflow;
in {
  options.my.claudeSpecflow.enable =
    lib.mkEnableOption "specflow on-demand multi-agent dev workflow scaffolder";

  config = lib.mkIf cfg.enable {
    # Materialise the generator command and the canonical template bundle into the
    # user-scope Claude Code config. The /specflow command copies this template into a
    # target repo on demand; it is never auto-run. Hooks under the template keep their
    # executable bit because the committed .sh files are mode 0755 (Nix preserves it).
    home.file = {
      ".claude/commands/specflow.md".source = ./claude-specflow/commands/specflow.md;
      ".claude/templates/specflow" = {
        source = ./claude-specflow/templates/specflow;
        recursive = true;
      };
    };

    # Contribute the specflow section to the assembled ~/.claude/CLAUDE.md (claude-code.nix
    # owns the file and joins all contributed sections).
    my.claudeCode.claudeMdSections = [
      (builtins.readFile ./claude-specflow/claude-md-section.md)
    ];
  };
}
