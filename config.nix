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
  users = [
    {
      username = "gfoster";
      systems = ["x86_64-linux"];
    }
    {
      # Corporate/AD account username — numeric usernames are valid on macOS
      username = "888973";
      systems = ["aarch64-darwin"];
    }
    # Add more users/systems:
    # {
    #   username = "alice";
    #   systems = [ "x86_64-linux" "aarch64-darwin" ];
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
