package system

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type Process struct {
	PID  int
	PPID int
	Comm string
}

func PsTree() (map[int]Process, error) {
	out, err := exec.Command("ps", "-A", "-o", "pid=,ppid=,comm=").Output()
	if err != nil {
		return nil, fmt.Errorf("ps: %w", err)
	}
	tree := map[int]Process{}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 {
			continue
		}
		pid, err1 := strconv.Atoi(f[0])
		ppid, err2 := strconv.Atoi(f[1])
		if err1 != nil || err2 != nil {
			continue
		}
		comm := strings.Join(f[2:], " ")
		comm = strings.TrimPrefix(comm, "[")
		comm = strings.TrimSuffix(comm, "]")
		tree[pid] = Process{PID: pid, PPID: ppid, Comm: comm}
	}
	return tree, nil
}

func DescendantsOf(tree map[int]Process, root int) []int {
	out := []int{root}
	frontier := []int{root}
	for len(frontier) > 0 {
		pid := frontier[0]
		frontier = frontier[1:]
		for cid, p := range tree {
			if p.PPID == pid {
				out = append(out, cid)
				frontier = append(frontier, cid)
			}
		}
	}
	return out
}

func FindSSH(tree map[int]Process, root int) int {
	for _, pid := range DescendantsOf(tree, root) {
		if pid == root {
			continue
		}
		switch tree[pid].Comm {
		case "ssh", "mosh-client":
			return pid
		}
	}
	return 0
}

func ProcessArgs(pid int) (string, error) {
	out, err := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "args=").Output()
	if err != nil {
		return "", nil
	}
	return strings.TrimSpace(string(out)), nil
}
