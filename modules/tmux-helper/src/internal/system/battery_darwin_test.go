//go:build darwin

package system

import "testing"

func TestParsePmsetBatt(t *testing.T) {
	cases := []struct {
		name     string
		in       string
		present  bool
		percent  int
		charging bool
	}{
		{
			name: "discharging on battery",
			in: `Now drawing from 'Battery Power'
 -InternalBattery-0 (id=12345)	87%; discharging; 4:32 remaining present: true`,
			present: true, percent: 87, charging: false,
		},
		{
			name: "charging on AC",
			in: `Now drawing from 'AC Power'
 -InternalBattery-0 (id=12345)	42%; charging; 1:13 remaining present: true`,
			present: true, percent: 42, charging: true,
		},
		{
			name: "fully charged",
			in: `Now drawing from 'AC Power'
 -InternalBattery-0 (id=12345)	100%; charged; 0:00 remaining present: true`,
			present: true, percent: 100, charging: true,
		},
		{
			name: "ac attached not charging",
			in: `Now drawing from 'AC Power'
 -InternalBattery-0 (id=12345)	100%; AC attached; not charging present: true`,
			present: true, percent: 100, charging: true,
		},
		{
			name:    "desktop mac no battery line",
			in:      `Now drawing from 'AC Power'`,
			present: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parsePmsetBatt(tc.in)
			if err != nil {
				t.Fatalf("parse err: %v", err)
			}
			if got.Present != tc.present {
				t.Errorf("Present: got %v want %v", got.Present, tc.present)
			}
			if !tc.present {
				return
			}
			if got.Percent != tc.percent {
				t.Errorf("Percent: got %d want %d", got.Percent, tc.percent)
			}
			if got.Charging != tc.charging {
				t.Errorf("Charging: got %v want %v", got.Charging, tc.charging)
			}
		})
	}
}
