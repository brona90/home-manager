{
  config,
  lib,
  ...
}: let
  cfg = config.my.claudeSkills;
in {
  options.my.claudeSkills.enable =
    lib.mkEnableOption "user-scope Claude Code skills and subagents";

  config = lib.mkIf cfg.enable {
    # Materialise the skill and agent bundles into the user-scope Claude Code
    # config. `recursive = true` links each file individually rather than making
    # the whole directory a store symlink, so an unmanaged skill dropped into
    # ~/.claude/skills by hand still works alongside these -- which matters
    # because a skill under active development is easier to iterate on in place
    # before it is promoted into this module.
    home.file = {
      ".claude/skills" = {
        source = ./claude-skills/skills;
        recursive = true;
      };
      ".claude/agents" = {
        source = ./claude-skills/agents;
        recursive = true;
      };
    };
  };
}
