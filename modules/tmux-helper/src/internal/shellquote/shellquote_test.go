package shellquote

import "testing"

func TestQuote(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"plain", "foo", `'foo'`},
		{"empty", "", `''`},
		{"space", "foo bar", `'foo bar'`},
		{"dollar", "$HOME", `'$HOME'`},
		{"backtick", "`id`", "'`id`'"},
		{"single quote", "it's", `'it'"'"'s'`},
		{"injection attempt", `'; rm -rf ~; '`, `''"'"'; rm -rf ~; '"'"''`},
		{"double quotes", `say "hi"`, `'say "hi"'`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Quote(tt.in); got != tt.want {
				t.Errorf("Quote(%q) = %s, want %s", tt.in, got, tt.want)
			}
		})
	}
}

func TestQuoteAll(t *testing.T) {
	got := QuoteAll([]string{"a", "b c"})
	want := []string{`'a'`, `'b c'`}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("got[%d] = %s, want %s", i, got[i], want[i])
		}
	}
}
