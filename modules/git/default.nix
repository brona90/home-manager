{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.git;
in
{
  options.modules.git = {
    enable = mkEnableOption "Gregory's git configuration";

    userName = mkOption {
      type = types.str;
      default = "Gregory Foster";
      description = "Git user name";
    };

    userEmail = mkOption {
      type = types.str;
      default = "brona90@gmail.com";
      description = "Git user email";
    };

    extraAliases = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional git aliases";
    };

    extraIgnores = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional global gitignore patterns";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      userName = cfg.userName;
      userEmail = cfg.userEmail;

      aliases = {
        st = "status";
        s = "status -s";
        ci = "commit";
        cm = "commit -m";
        ca = "commit --amend";
        cam = "commit --amend -m";
        a = "add";
        aa = "add -A";
        ap = "add -p";
        co = "checkout";
        cob = "checkout -b";
        br = "branch";
        brd = "branch -d";
        brD = "branch -D";
        l = "log --oneline --graph --decorate";
        lg = "log --oneline --graph --decorate --all";
        ll = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        d = "diff";
        ds = "diff --staged";
        dc = "diff --cached";
        stash-all = "stash save --include-untracked";
        pf = "push --force-with-lease";
        pl = "pull";
        plo = "pull origin";
        psh = "push";
        psho = "push origin";
        rb = "rebase";
        rbi = "rebase -i";
        rbc = "rebase --continue";
        rba = "rebase --abort";
        unstage = "restore --staged";
        uncommit = "reset --soft HEAD~1";
      } // cfg.extraAliases;

      ignores = [
        ".DS_Store"
        "Thumbs.db"
        "*~"
        "*.swp"
        "*.swo"
        ".vscode/"
        ".idea/"
        "result"
        "result-*"
        ".direnv/"
        "node_modules/"
        "__pycache__/"
        "*.pyc"
        ".pytest_cache/"
        "target/"
        "*.class"
      ] ++ cfg.extraIgnores;

      extraConfig = {
        init.defaultBranch = "main";
        core.editor = "emacs -nw";
        pull.rebase = false;
        push.autoSetupRemote = true;
        diff.algorithm = "histogram";
        rerere.enabled = true;
        color.ui = "auto";
        branch.sort = "-committerdate";
      };
    };

    # Force overwrite if conflicts exist
    xdg.configFile."git/config".force = true;
    xdg.configFile."git/ignore".force = true;
  };
}
