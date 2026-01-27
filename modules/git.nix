{ config, lib, pkgs, ... }:

let
  cfg = config.my.git;
in
{
  options.my.git = {
    enable = lib.mkEnableOption "Git configuration";

    userName = lib.mkOption {
      type = lib.types.str;
      default = "Gregory Foster";
      description = "Git user name";
    };

    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "brona90@gmail.com";
      description = "Git user email";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional git config";
    };
  };

  config = lib.mkIf cfg.enable {
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
          lg = "log --graph --all --format='%C(yellow)%h%Creset %s %C(cyan)<%ae>%Creset %C(green)(%cr)%Creset%C(auto)%d%Creset'";
          ll = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          le = "log --oneline --format='%C(yellow)%h%Creset %s %C(cyan)<%ae>%Creset'";
          lle = "log --format='%C(yellow)%h%Creset %s %C(cyan)<%ae>%Creset %C(green)(%cr)%Creset'";
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

    xdg.configFile = {
      "git/config".force = true;
      "git/ignore".force = true;
    };
  };
}
