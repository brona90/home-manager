package tmux

// DisplayMessage runs `tmux display-message -p <format>` and returns the
// expanded result. Any tmux #{...} format spec is honored.
func DisplayMessage(format string) (string, error) {
	return OutputTrim("display-message", "-p", format)
}

// GlobalOption returns the value of a global option (`tmux show-options -gv <name>`).
func GlobalOption(name string) (string, error) {
	return OutputTrim("show-options", "-gv", name)
}

// SetGlobalOption sets a global option (`tmux set-option -g <name> <value>`).
func SetGlobalOption(name, value string) error {
	return Run("set-option", "-g", name, value)
}
