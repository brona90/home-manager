package clipboard

import (
	"errors"
	"os/exec"
	"testing"
)

// fakeLookPath returns a Lookup function that succeeds for the listed names.
func fakeLookPath(present ...string) LookPathFunc {
	set := map[string]bool{}
	for _, n := range present {
		set[n] = true
	}
	return func(name string) (string, error) {
		if set[name] {
			return "/fake/" + name, nil
		}
		return "", &exec.Error{Name: name, Err: exec.ErrNotFound}
	}
}

func fakeEnv(env map[string]string) GetenvFunc {
	return func(k string) string { return env[k] }
}

func TestDetect(t *testing.T) {
	tests := []struct {
		name     string
		goos     string
		path     []string
		env      map[string]string
		wantName string
		wantErr  bool
	}{
		{"darwin pbcopy", "darwin", []string{"pbcopy"}, nil, "pbcopy", false},
		{"darwin missing", "darwin", []string{}, nil, "", true},
		{"linux wayland", "linux", []string{"wl-copy"}, map[string]string{"WAYLAND_DISPLAY": ":0"}, "wl-copy", false},
		{"linux x11 xclip", "linux", []string{"xclip"}, map[string]string{"DISPLAY": ":0"}, "xclip", false},
		{"linux x11 xsel fallback", "linux", []string{"xsel"}, map[string]string{"DISPLAY": ":0"}, "xsel", false},
		{"linux x11 prefers xclip over xsel", "linux", []string{"xclip", "xsel"}, map[string]string{"DISPLAY": ":0"}, "xclip", false},
		{"wsl prefers clip.exe over X", "linux", []string{"clip.exe", "xclip"}, map[string]string{"WSL_DISTRO_NAME": "Ubuntu", "DISPLAY": ":0"}, "clip.exe", false},
		{"linux no env no tools", "linux", []string{}, nil, "", true},
		{"linux bare clip.exe last resort", "linux", []string{"clip.exe"}, nil, "clip.exe", false},
		{"unsupported platform", "freebsd", []string{}, nil, "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b, err := Detect(tt.goos, fakeLookPath(tt.path...), fakeEnv(tt.env))
			if (err != nil) != tt.wantErr {
				t.Errorf("err = %v, wantErr = %v", err, tt.wantErr)
				return
			}
			if tt.wantErr {
				if !errors.Is(err, ErrNoBackend) {
					t.Errorf("want ErrNoBackend, got %v", err)
				}
				return
			}
			if b.Name != tt.wantName {
				t.Errorf("got %q, want %q", b.Name, tt.wantName)
			}
		})
	}
}
