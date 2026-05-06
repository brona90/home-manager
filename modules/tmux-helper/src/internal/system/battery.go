package system

// Battery reports the current battery state. Present is false when the
// host has no battery (desktops, WSL, headless servers); callers should
// render nothing in that case.
type Battery struct {
	Present  bool
	Percent  int
	Charging bool
}
