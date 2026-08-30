package host

import "os"

// DefaultEvidenceRoot resolves private evidence storage from environment or user home.
func DefaultEvidenceRoot(environment map[string]string) string {
	if root := environment["BNEST_RESOURCE_ROOT"]; root != "" {
		return root
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home + "/bnest/runtime/resource-guard"
}
