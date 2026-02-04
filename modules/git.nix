{ config, lib, gitConfig, ... }:

let
  cfg = config.my.git;
in
{
  options.my.git = {
    enable = lib.mkEnableOption "Git configuration";

    userName = lib.mkOption {
      type = lib.types.str;
      default = gitConfig.userName;
      description = "Git user name";
    };

    userEmail = lib.mkOption {
      type = lib.types.str;
      default = gitConfig.userEmail;
      description = "Git user email";
    };

    signing = {
      enable = lib.mkEnableOption "GPG commit signing";

      key = lib.mkOption {
        type = lib.types.str;
        default = gitConfig.signingKey;
        description = "GPG key ID for signing commits (from config.nix)";
      };

      signByDefault = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Sign all commits by default";
      };
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

      signing = lib.mkIf cfg.signing.enable {
        inherit (cfg.signing) key signByDefault;
      };

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

        # GPG program for signing
        gpg.program = lib.mkIf cfg.signing.enable "gpg";
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
