# User configuration - edit this file for your setup
#
# Add your username and the systems you use.
# Run `nix eval --impure --raw --expr 'builtins.currentSystem'` to find your system.
{
  users = [
    {
      username = "gfoster";
      systems = [ "x86_64-linux" ];
      # email = "your@email.com";  # Optional: override git email
    }
    {
      username = "888973";
      systems = [ "aarch64-darwin" ];
    }
    # Add more users/systems:
    # {
    #   username = "alice";
    #   systems = [ "x86_64-linux" "aarch64-darwin" ];
    # }
  ];

  # Default git config (can be overridden per-user above)
  git = {
    userName = "Gregory Foster";
    userEmail = "brona90@gmail.com";
  };
}
