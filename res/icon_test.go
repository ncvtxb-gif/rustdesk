package res

import (
	"encoding/binary"
	"os"
	"reflect"
	"sort"
	"testing"
)

func TestWindowsApplicationIconsContainRequiredSizes(t *testing.T) {
	want := []int{16, 32, 48, 64, 128, 256}
	for _, path := range []string{
		"icon.ico",
		"../flutter/windows/runner/resources/app_icon.ico",
	} {
		t.Run(path, func(t *testing.T) {
			if got := icoSizes(t, path); !reflect.DeepEqual(got, want) {
				t.Fatalf("ICO sizes = %v, want %v", got, want)
			}
		})
	}
}

func TestWindowsTrayIconContainsSmallSizes(t *testing.T) {
	want := []int{16, 24, 32}
	if got := icoSizes(t, "tray-icon.ico"); !reflect.DeepEqual(got, want) {
		t.Fatalf("ICO sizes = %v, want %v", got, want)
	}
}

func icoSizes(t *testing.T, path string) []int {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if len(data) < 6 || binary.LittleEndian.Uint16(data[2:4]) != 1 {
		t.Fatalf("%s is not a Windows ICO file", path)
	}

	count := int(binary.LittleEndian.Uint16(data[4:6]))
	if len(data) < 6+count*16 {
		t.Fatalf("%s has a truncated ICO directory", path)
	}

	sizes := make([]int, 0, count)
	for i := 0; i < count; i++ {
		width := int(data[6+i*16])
		height := int(data[7+i*16])
		if width == 0 {
			width = 256
		}
		if height == 0 {
			height = 256
		}
		if width != height {
			t.Fatalf("%s contains a non-square entry: %dx%d", path, width, height)
		}
		sizes = append(sizes, width)
	}
	sort.Ints(sizes)
	return sizes
}
