package system

import "testing"

func TestDescendantsOf(t *testing.T) {
	tree := map[int]Process{
		1:  {PID: 1, PPID: 0, Comm: "init"},
		10: {PID: 10, PPID: 1, Comm: "tmux"},
		20: {PID: 20, PPID: 10, Comm: "zsh"},
		30: {PID: 30, PPID: 20, Comm: "ssh"},
		40: {PID: 40, PPID: 1, Comm: "other"},
	}
	got := DescendantsOf(tree, 10)
	want := map[int]bool{10: true, 20: true, 30: true}
	if len(got) != len(want) {
		t.Fatalf("got %v, want PIDs %v", got, want)
	}
	for _, pid := range got {
		if !want[pid] {
			t.Errorf("unexpected pid %d in descendants", pid)
		}
	}
}

func TestFindSSH(t *testing.T) {
	tree := map[int]Process{
		1:  {PID: 1, PPID: 0, Comm: "init"},
		10: {PID: 10, PPID: 1, Comm: "tmux"},
		20: {PID: 20, PPID: 10, Comm: "zsh"},
		30: {PID: 30, PPID: 20, Comm: "ssh"},
	}
	if got := FindSSH(tree, 10); got != 30 {
		t.Errorf("got %d, want 30", got)
	}
}

func TestFindSSH_NoMatch(t *testing.T) {
	tree := map[int]Process{
		10: {PID: 10, PPID: 1, Comm: "tmux"},
		20: {PID: 20, PPID: 10, Comm: "zsh"},
		30: {PID: 30, PPID: 20, Comm: "vim"},
	}
	if got := FindSSH(tree, 10); got != 0 {
		t.Errorf("got %d, want 0", got)
	}
}

func TestFindSSH_Mosh(t *testing.T) {
	tree := map[int]Process{
		10: {PID: 10, PPID: 1, Comm: "tmux"},
		20: {PID: 20, PPID: 10, Comm: "zsh"},
		30: {PID: 30, PPID: 20, Comm: "mosh-client"},
	}
	if got := FindSSH(tree, 10); got != 30 {
		t.Errorf("got %d, want 30 (mosh-client)", got)
	}
}
