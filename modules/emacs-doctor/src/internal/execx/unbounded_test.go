package execx

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// allowedRawExec lists the only functions (file:func, relative to the module
// root) that may start a process without going through Run. Each entry must
// bound the process some other way.
var allowedRawExec = map[string]string{
	// A long-lived GUI app, not a query: bounded by its own deadline, then the
	// process group is killed and reaped.
	"cmds/guiprobe.go:launchAndTime": "deadline + process-group kill",
}

// rawExecFuncs are the calls that start a process. exec.LookPath is not one.
var rawExecFuncs = map[string]map[string]bool{
	"os/exec": {"Command": true, "CommandContext": true},
	"os":      {"StartProcess": true},
	"syscall": {"ForkExec": true, "Exec": true, "StartProcess": true},
}

// Every exec in emacs-doctor must be bounded: the tool is run when the daemon
// or the user bus is wedged, and an unbounded emacsclient/systemctl call hangs
// it on exactly the thing it is diagnosing. Run is the bounded path; this
// test fails if a call site starts a process any other way, so the rule cannot
// be undone by one careless edit.
func TestNoUnboundedExec(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	self, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}
	scanned := 0
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if path == self {
				return filepath.SkipDir // Run itself is the one sanctioned caller
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		scanned++
		for _, v := range rawExecCalls(t, path) {
			key := filepath.ToSlash(rel) + ":" + v.fn
			if _, ok := allowedRawExec[key]; ok {
				continue
			}
			t.Errorf("%s:%d: %s in %s starts a process without a timeout; use execx.Run",
				filepath.ToSlash(rel), v.line, v.call, v.fn)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	// Guard against the walk silently finding nothing (wrong root) and passing.
	if scanned < 5 {
		t.Fatalf("scanned only %d source files under %s; the walk root is wrong", scanned, root)
	}
}

type rawCall struct {
	fn, call string
	line     int
}

func rawExecCalls(t *testing.T, path string) []rawCall {
	t.Helper()
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
	if err != nil {
		t.Fatalf("parse %s: %v", path, err)
	}
	// Local name -> import path, so an aliased import is still caught.
	names := map[string]string{}
	for _, imp := range f.Imports {
		p, _ := strconv.Unquote(imp.Path.Value)
		if _, ok := rawExecFuncs[p]; !ok {
			continue
		}
		name := p[strings.LastIndex(p, "/")+1:]
		if imp.Name != nil {
			name = imp.Name.Name
		}
		names[name] = p
	}
	var found []rawCall
	for _, decl := range f.Decls {
		fn := "<package scope>"
		if fd, ok := decl.(*ast.FuncDecl); ok {
			fn = fd.Name.Name
		}
		ast.Inspect(decl, func(n ast.Node) bool {
			sel, ok := n.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			id, ok := sel.X.(*ast.Ident)
			if !ok {
				return true
			}
			if p, ok := names[id.Name]; ok && rawExecFuncs[p][sel.Sel.Name] {
				found = append(found, rawCall{fn, id.Name + "." + sel.Sel.Name, fset.Position(sel.Pos()).Line})
			}
			return true
		})
	}
	return found
}
