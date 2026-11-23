package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// allowedUnbounded lists the only functions (file:func, relative to the
// module root) that may run a process with no time bound, and why.
var allowedUnbounded = map[string]string{
	// display-popup -E blocks until the user closes the popup, which can
	// take any amount of time; every other tmux call goes through Run.
	"internal/tmux/cmd.go:RunInteractive": "waits on the user by design",
}

// rawExec are calls that start a process with no context at all.
var rawExec = map[string]map[string]bool{
	"os/exec": {"Command": true},
	"os":      {"StartProcess": true},
	"syscall": {"ForkExec": true, "Exec": true, "StartProcess": true},
}

// TestNoUnboundedExec: every process tmux-helper starts must be bounded. It
// runs from tmux key bindings and status-interval refreshes, so a hung tmux,
// emacsclient, ssh, ps, sysctl or clipboard tool otherwise wedges a binding
// or stacks up one stuck helper per refresh. Two rules, checked over every
// non-test .go file whatever its build tags (go/parser ignores them, so the
// darwin-only files are covered on Linux):
//
//  1. No exec.Command, os.StartProcess or syscall exec: they take no context.
//  2. context.Background() / context.TODO() appear only as the first argument
//     of context.WithTimeout or context.WithDeadline. That is how a bounded
//     context is made, and it also catches the unbounded ones that never touch
//     exec directly -- `ctx := context.Background()` handed to
//     exec.CommandContext, or passed to a command-builder var such as
//     tmuxCommand, which is exactly how RunInteractive works.
func TestNoUnboundedExec(t *testing.T) {
	scanned := 0
	used := map[string]bool{}
	err := filepath.WalkDir(".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		scanned++
		rel := filepath.ToSlash(path)
		for _, v := range unboundedCalls(t, path) {
			key := rel + ":" + v.fn
			if _, ok := allowedUnbounded[key]; ok {
				used[key] = true
				continue
			}
			t.Errorf("%s:%d: %s in %s %s", rel, v.line, v.call, v.fn, v.why)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	// Guard against the walk silently finding nothing (wrong root) and passing.
	if scanned < 20 {
		t.Fatalf("scanned only %d source files; the walk root is wrong", scanned)
	}
	var stale []string
	for key := range allowedUnbounded {
		if !used[key] {
			stale = append(stale, key)
		}
	}
	sort.Strings(stale)
	for _, key := range stale {
		t.Errorf("allowedUnbounded entry %s matched nothing; remove it", key)
	}
}

type unboundedCall struct {
	fn, call, why string
	line          int
}

func unboundedCalls(t *testing.T, path string) []unboundedCall {
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
		if _, ok := rawExec[p]; !ok && p != "context" {
			continue
		}
		name := p[strings.LastIndex(p, "/")+1:]
		if imp.Name != nil {
			name = imp.Name.Name
		}
		names[name] = p
	}
	// pkgFunc reports the import path and name of a pkg.Func expression.
	pkgFunc := func(e ast.Expr) (string, string) {
		sel, ok := e.(*ast.SelectorExpr)
		if !ok {
			return "", ""
		}
		id, ok := sel.X.(*ast.Ident)
		if !ok {
			return "", ""
		}
		return names[id.Name], sel.Sel.Name
	}
	isRootCtx := func(e ast.Expr) bool {
		call, ok := e.(*ast.CallExpr)
		if !ok {
			return false
		}
		p, fn := pkgFunc(call.Fun)
		return p == "context" && (fn == "Background" || fn == "TODO")
	}

	var found []unboundedCall
	for _, decl := range f.Decls {
		fn := "<package scope>"
		if fd, ok := decl.(*ast.FuncDecl); ok {
			fn = fd.Name.Name
		}
		// First pass: the root contexts that are immediately bounded.
		bounded := map[ast.Expr]bool{}
		ast.Inspect(decl, func(n ast.Node) bool {
			if call, ok := n.(*ast.CallExpr); ok && len(call.Args) > 0 {
				if p, name := pkgFunc(call.Fun); p == "context" && (name == "WithTimeout" || name == "WithDeadline") {
					bounded[call.Args[0]] = true
				}
			}
			return true
		})
		ast.Inspect(decl, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			p, name := pkgFunc(call.Fun)
			line := fset.Position(call.Pos()).Line
			switch {
			case rawExec[p][name]:
				found = append(found, unboundedCall{fn, p + "." + name,
					"starts a process with no context; use exec.CommandContext with a bounded one", line})
			case isRootCtx(call) && !bounded[call]:
				found = append(found, unboundedCall{fn, "context." + name,
					"is an unbounded context; wrap it in context.WithTimeout", line})
			}
			return true
		})
	}
	return found
}
