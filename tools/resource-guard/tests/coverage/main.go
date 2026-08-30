package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func run() int {
	profile := flag.String("profile", "", "Go coverage profile")
	files := flag.String("files", "", "comma-separated production files")
	minimum := flag.Float64("minimum", 99, "minimum covered statement percentage")
	flag.Parse()
	selected := map[string]bool{}
	for file := range strings.SplitSeq(*files, ",") {
		selected[strings.TrimSpace(file)] = true
	}
	input, err := os.Open(*profile)
	if err != nil {
		panic(err)
	}
	defer func() { _ = input.Close() }()
	covered, total := 0, 0
	scanner := bufio.NewScanner(input)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 3 || fields[0] == "mode:" {
			continue
		}
		location := fields[0]
		colon := strings.LastIndex(location, ":")
		if colon < 0 {
			continue
		}
		path := location[:colon]
		matched := false
		for file := range selected {
			if strings.HasSuffix(path, file) {
				matched = true
				break
			}
		}
		if !matched {
			continue
		}
		statements, parseError := strconv.Atoi(fields[1])
		if parseError != nil {
			panic(parseError)
		}
		count, parseError := strconv.Atoi(fields[2])
		if parseError != nil {
			panic(parseError)
		}
		total += statements
		if count > 0 {
			covered += statements
		}
	}
	if err := scanner.Err(); err != nil {
		panic(err)
	}
	if total == 0 {
		panic("coverage selection matched no statements")
	}
	percentage := float64(covered) * 100 / float64(total)
	_, _ = fmt.Fprintf(os.Stdout, "selected production line coverage: %.2f%% (%d/%d statements)\n", percentage, covered, total)
	if percentage < *minimum {
		return 1
	}
	return 0
}

func main() { os.Exit(run()) }
