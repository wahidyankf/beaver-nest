package main

import (
	"os"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/cli"
)

func main() { os.Exit(cli.Execute(os.Args[1:])) }
