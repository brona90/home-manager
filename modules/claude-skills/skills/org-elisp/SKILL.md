---
name: org-elisp
description: Writing Emacs Lisp that parses or generates Org-mode text under `emacs -Q --batch`, and the silent-corruption traps that come with it. Use this skill whenever a task involves .el files, org-element, batch Emacs builds, Org tags or properties, generating JSON from Elisp, or golden-file test fixtures — and specifically when working in the orrery repo, when a build writes JSON, or when Org text appears mangled, untagged, or truncated for no obvious reason. The failures here do not raise errors, so reach for this before debugging rather than after.
---

# Batch Elisp and Org text

The bugs in this domain share a shape: nothing errors, the output is
structurally valid, and the content is wrong. They are found by reading output,
not by reading stack traces. Two have already cost real time on this machine and
are worth knowing before you write a line.

## json-serialize returns a unibyte string

`json-serialize` hands back a unibyte string holding UTF-8 *bytes*. Insert that
into a multibyte buffer and every byte of a non-ASCII character becomes a
separate raw eight-bit char. Call `json-pretty-print-buffer` afterwards and it
re-serialises those raw bytes as escapes, so an em-dash reaches the file as the
literal text `\342\200\224`.

```elisp
(insert (decode-coding-string (json-serialize obj) 'utf-8))
```

Binding `coding-system-for-write` does not help — the corruption happens on the
way *in*, not on the way out.

This shipped to a live dashboard for a week (31 occurrences in one build). What
let it through is the more useful lesson: **a golden fixture containing only
ASCII cannot catch an encoding bug.** Put a non-ASCII character in the fixtures,
and put it somewhere the build will not truncate — an em-dash in an item that
falls outside a panel's `:LIMIT:` is not covered by anything.

## Org tags cannot contain hyphens

`org-tag-re` matches `[[:alnum:]_@#%]+` only. A headline ending
`:dark-energy:` is not parsed as tags at all: the text stays glued to the
headline and org-element reports no tags. Use underscores — `dark_energy`.

`org-tag-re` is a plain `defvar` and so is let-bindable, but widening it is the
wrong fix. org-element is the definition of what Org means, so a program that
accepts hyphenated tags will disagree with what Gregory's own Emacs shows for
the same file.

When this turns up across a whole corpus, fix the **example authors copy from**,
not just the authors. In orrery a third of the feed had lost its tags because
the contract example in `README.org` itself read `:condensed-matter:`; repairing
the writers without repairing the example would have let it regrow.

## Keep the build pure so it can be gated

Anything that varies per run — the clock, git provenance — is passed *in* as an
argument rather than read inside the builder. That is what makes byte-identical
golden comparison possible at all:

```elisp
(orrery-build-ir profile panels feed intents provenance generated-at)
```

Only the outermost batch entry point calls `orrery-now` / `orrery-provenance`.
Golden tests pass fixed values instead. If you find yourself wanting to stub a
clock, the signature is wrong.

## Gates, not tests

Verification runs under `emacs -Q --batch` with byte-compile warnings treated as
errors, plus schema, golden, and docs gates. A gate that fails is telling you
something; work out what it was guarding before weakening it. `make
golden-accept` rewrites the baseline, which turns a regression into the new
truth if you run it without reading the diff first.

Golden coverage is deliberately non-redundant: `ir.json` carries each panel cut
to its `:LIMIT:` and only open entries, while `archive.json` carries everything.
A fixture item truncated out of one is visible in the other, so both are gated.

## One writer per format

There is exactly one function that knows how to format an inbox entry
(`orrery-inbox-file-entry`), and every surface — CLI, Emacs, MCP, the GitHub
Actions intake — goes through it. A surface is a way of *authoring Org text*,
not an integration. When adding a surface, the thing to check is that it did not
become a second implementation of the format; that is the mistake `bin/orrery`
exists as a 15-line shim to prevent.

## Related

Running these builds from a Windows session goes through
[wsl-interop](../wsl-interop/SKILL.md).
