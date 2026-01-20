{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.my.git;
in
{
  options.my.git = {
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

    extraConfig = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional git config";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;

      settings = {
        user = {
          name = cfg.userName;
          email = cfg.userEmail;
        };
        init.defaultBranch = "main";
        core.editor = "emacs -nw";
        pull.rebase = false;
        push.autoSetupRemote = true;
        diff.algorithm = "histogram";
        rerere.enabled = true;
        color.ui = "auto";
        branch.sort = "-committerdate";

        alias = {
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
        };
      } // cfg.extraConfig;

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
      ];

    };

    # Force overwrite to handle conflicts with existing files
    xdg.configFile."git/config".force = true;
    xdg.configFile."git/ignore".force = true;
  };
}
