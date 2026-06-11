# Repository configuration
# Fork this repo and update these values for your setup
{
  # Repository settings (used by CI and bootstrap)
  repo = {
    # GitHub username/org (for clone URL and Docker image naming)
    owner = "brona90";

    # Repository name
    name = "home-manager";

    # Docker Hub username (where images are pushed)
    dockerHubUser = "brona90";

    # Cachix cache name
    cachixCache = "gfoster";

    # Cachix public signing key (find it at https://app.cachix.org → your cache → Settings)
    cachixPublicKey = "gfoster.cachix.org-1:aS1bQZ5bnWN20b66zHBuQY5dc5WD0hzUWMsYm3d/xgA=";
  };

  # User configurations
  #
  # `hosts` (optional) maps a system to a host module under
  # home/hosts/<name>.nix. Host modules carry machine-specific config that
  # doesn't belong in the generic platform profiles (home/linux.nix,
  # home/darwin.nix): Homebrew package lists, distributed-build farms, WSL
  # interop, corporate network workarounds, etc. A system with no mapping
  # gets only the generic platform profile.
  #
  # Forks: add your own files under home/hosts/ and point these mappings at
  # them, or drop the `hosts` attribute entirely. Host-internal data (e.g.
  # the Homebrew lists) can also be overridden without editing tracked files
  # via config.local.nix — see config.local.nix.example.
  #
  # NOTE: home/hosts/ (home-manager host layer) is unrelated to the
  # top-level hosts/ directory, which holds NixOS system configurations.
  users = [
    {
      username = "gfoster";
      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"];
      hosts = {
        "x86_64-linux" = "wsl"; # NixOS-WSL box: build farm, GPG bridge, /mnt/c aliases
        "x86_64-darwin" = "personal-mac"; # Intel MacBook
        "aarch64-darwin" = "personal-mac"; # Apple Silicon MacBook
      };
    }
    {
      # Corporate/AD account username — numeric usernames are valid on macOS
      username = "888973";
      systems = ["aarch64-darwin"];
      hosts."aarch64-darwin" = "corp-mac"; # corporate Mac: Zscaler bypass, work apps
    }
    # Add more users/systems:
    # {
    #   username = "alice";
    #   systems = [ "x86_64-linux" "aarch64-darwin" ];
    #   hosts."aarch64-darwin" = "alices-mac"; # -> home/hosts/alices-mac.nix
    # }
  ];

  # Default git identity — override in config.local.nix (gitignored) on
  # personal machines so these values stay out of the public commit history.
  git = {
    userName = "Gregory Foster";
    userEmail = "brona90@gmail.com";
    signingKey = "ECA2632B08E80FC6"; # GPG key ID for commit signing
  };
}
