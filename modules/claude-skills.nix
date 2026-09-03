{
  config,
  lib,
  ...
}: let
  cfg = config.my.claudeSkills;

  bundle = ./claude-skills;

  # Every file in the bundle, relative to it. WALKED rather than listed so that
  # adding a skill is one new file and no bookkeeping anywhere else, and so a
  # skill that is more than a lone SKILL.md (references, helper scripts) crosses
  # whole rather than losing the parts nobody remembered to enumerate.
  relPaths =
    map (p: lib.removePrefix "${toString bundle}/" (toString p))
    (lib.filesystem.listFilesRecursive bundle);
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

    # THE SECOND CONSUMER OF THE SAME BUNDLE. Claude Code also runs natively on
    # Windows here, against these same repositories, and reads its skills and
    # subagents from C:\Users\<winuser>\.claude -- which home.file above cannot
    # reach. Those copies were made by hand in August and then diverged, which is
    # not a hypothetical: the Windows copy of the nix-home-manager skill still
    # instructs agents to edit modules/emacs/doom.d/ in a repository where Doom
    # has been retired, and the Windows nix-module-author agent predates the
    # verify.sh gate, the git-add-before-build rule and the lint-tools rule. A
    # stale skill is worse than an absent one: it is wrong instructions delivered
    # with the authority of a managed file.
    #
    # `own', not `merge-json': these are whole files whose single writer is this
    # repository. Per-file rather than per-directory, matching home.file's
    # `recursive = true' above and for the same reason -- a skill under
    # development, dropped into that directory by hand, keeps working beside
    # them, and the bridge never deletes what it did not write.
    my.windowsBridge.files = lib.listToAttrs (map (rel: {
        name = "claude-${lib.replaceStrings ["/" "."] ["-" "-"] rel}";
        value = {
          target = ".claude/${rel}";
          mode = "own";
          text = builtins.readFile (bundle + "/${rel}");
        };
      })
      relPaths);
  };
}
