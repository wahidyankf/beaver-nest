package config

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/policy"
)

const schemaVersion = 1

// Result contains the validated catalog without retaining local file contents.
type Result struct {
	Catalog policy.Catalog
	Hash    string
	Source  string
}

type profileOverride struct {
	Extends                    string   `json:"extends,omitempty"`
	Fallback                   *string  `json:"fallback,omitempty"`
	Strict                     *bool    `json:"strict,omitempty"`
	MemoryReservePercent       *float64 `json:"memoryReservePercent,omitempty"`
	MemoryReserveMinMiB        *int64   `json:"memoryReserveMinMiB,omitempty"`
	MemoryReserveMaxMiB        *int64   `json:"memoryReserveMaxMiB,omitempty"`
	NoSwapMemoryReservePercent *float64 `json:"noSwapMemoryReservePercent,omitempty"`
	NoSwapMemoryReserveMinMiB  *int64   `json:"noSwapMemoryReserveMinMiB,omitempty"`
	NoSwapMemoryReserveMaxMiB  *int64   `json:"noSwapMemoryReserveMaxMiB,omitempty"`
	DiskReservePercent         *float64 `json:"diskReservePercent,omitempty"`
	DiskReserveMinMiB          *int64   `json:"diskReserveMinMiB,omitempty"`
	DiskReserveMaxMiB          *int64   `json:"diskReserveMaxMiB,omitempty"`
	MaxConcurrency             *int     `json:"maxConcurrency,omitempty"`
	MaxCPUUtilizationPercent   *float64 `json:"maxCpuUtilizationPercent,omitempty"`
}

type file struct {
	SchemaVersion  int                        `json:"schemaVersion"`
	DefaultProfile string                     `json:"defaultProfile,omitempty"`
	Profiles       map[string]profileOverride `json:"profiles,omitempty"`
}

func consumeJSON(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, isDelimiter := token.(json.Delim)
	if !isDelimiter {
		return nil
	}
	switch delimiter {
	case '{':
		seen := map[string]bool{}
		for decoder.More() {
			keyToken, keyError := decoder.Token()
			if keyError != nil {
				return keyError
			}
			key, ok := keyToken.(string)
			if !ok {
				return errors.New("JSON object key is not a string")
			}
			if seen[key] {
				return fmt.Errorf("duplicate JSON field %q", key)
			}
			seen[key] = true
			if valueError := consumeJSON(decoder); valueError != nil {
				return valueError
			}
		}
	case '[':
		for decoder.More() {
			if itemError := consumeJSON(decoder); itemError != nil {
				return itemError
			}
		}
	}
	_, err = decoder.Token()
	return err
}

func decode(data []byte) (file, error) {
	duplicateDecoder := json.NewDecoder(bytes.NewReader(data))
	if err := consumeJSON(duplicateDecoder); err != nil {
		return file{}, err
	}
	if _, err := duplicateDecoder.Token(); !errors.Is(err, io.EOF) {
		return file{}, errors.New("configuration must contain one JSON value")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var decoded file
	if err := decoder.Decode(&decoded); err != nil {
		return file{}, err
	}
	return decoded, nil
}

func setFloat(target, override *float64) {
	if override != nil {
		*target = *override
	}
}

func setBytes(target, override *int64) {
	if override != nil {
		*target = *override * policy.MiB
	}
}

func apply(name string, base policy.Profile, override profileOverride) policy.Profile {
	base.Name = name
	if override.Fallback != nil {
		base.Fallback = *override.Fallback
	}
	if override.Strict != nil {
		base.Strict = *override.Strict
	}
	setFloat(&base.MemoryReservePercent, override.MemoryReservePercent)
	setBytes(&base.MemoryReserveMinBytes, override.MemoryReserveMinMiB)
	setBytes(&base.MemoryReserveMaxBytes, override.MemoryReserveMaxMiB)
	setFloat(&base.NoSwapMemoryReservePercent, override.NoSwapMemoryReservePercent)
	setBytes(&base.NoSwapMemoryReserveMinBytes, override.NoSwapMemoryReserveMinMiB)
	setBytes(&base.NoSwapMemoryReserveMaxBytes, override.NoSwapMemoryReserveMaxMiB)
	setFloat(&base.DiskReservePercent, override.DiskReservePercent)
	setBytes(&base.DiskReserveMinBytes, override.DiskReserveMinMiB)
	setBytes(&base.DiskReserveMaxBytes, override.DiskReserveMaxMiB)
	if override.MaxConcurrency != nil {
		base.MaxConcurrency = *override.MaxConcurrency
	}
	setFloat(&base.MaxCPUUtilizationPercent, override.MaxCPUUtilizationPercent)
	return base
}

func validateProfile(profile policy.Profile) error {
	if profile.MemoryReservePercent <= 0 || profile.NoSwapMemoryReservePercent <= 0 || profile.DiskReservePercent <= 0 {
		return errors.New("reserve percentages must be positive")
	}
	if profile.MemoryReserveMinBytes < 128*policy.MiB || profile.NoSwapMemoryReserveMinBytes < 256*policy.MiB || profile.DiskReserveMinBytes < policy.HardDiskFloorBytes {
		return errors.New("profile weakens immutable safety floors")
	}
	if profile.MemoryReserveMaxBytes < profile.MemoryReserveMinBytes || profile.NoSwapMemoryReserveMaxBytes < profile.NoSwapMemoryReserveMinBytes || profile.DiskReserveMaxBytes < profile.DiskReserveMinBytes {
		return errors.New("profile reserve maximum is below its minimum")
	}
	if profile.MaxConcurrency < 0 || profile.MaxCPUUtilizationPercent <= 0 || profile.MaxCPUUtilizationPercent > 98 {
		return errors.New("profile CPU limits are invalid")
	}
	return nil
}

func buildCatalog(decoded file) (policy.Catalog, error) { //nolint:gocognit // Recursive inheritance and fallback validation deliberately share one graph walk.
	if decoded.SchemaVersion != schemaVersion {
		return policy.Catalog{}, fmt.Errorf("unsupported configuration schema %d", decoded.SchemaVersion)
	}
	catalog := policy.BuiltinCatalog()
	resolved := map[string]bool{}
	visiting := map[string]bool{}
	var resolve func(string) (policy.Profile, error)
	resolve = func(name string) (policy.Profile, error) {
		if resolved[name] {
			return catalog.Profiles[name], nil
		}
		if visiting[name] {
			return policy.Profile{}, fmt.Errorf("profile inheritance cycle at %q", name)
		}
		override, configured := decoded.Profiles[name]
		base, builtin := catalog.Profiles[name]
		if !configured {
			if !builtin {
				return policy.Profile{}, fmt.Errorf("unknown profile %q", name)
			}
			resolved[name] = true
			return base, nil
		}
		visiting[name] = true
		if override.Extends != "" {
			parent, err := resolve(override.Extends)
			if err != nil {
				return policy.Profile{}, err
			}
			base = parent
		} else if !builtin {
			return policy.Profile{}, fmt.Errorf("custom profile %q requires extends", name)
		}
		base = apply(name, base, override)
		if err := validateProfile(base); err != nil {
			return policy.Profile{}, fmt.Errorf("profile %q: %w", name, err)
		}
		delete(visiting, name)
		resolved[name] = true
		catalog.Profiles[name] = base
		return base, nil
	}
	names := make([]string, 0, len(decoded.Profiles))
	for name := range decoded.Profiles {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if _, err := resolve(name); err != nil {
			return policy.Catalog{}, err
		}
	}
	for name, profile := range catalog.Profiles {
		if profile.Fallback != "" {
			if _, exists := catalog.Profiles[profile.Fallback]; !exists {
				return policy.Catalog{}, fmt.Errorf("profile %q has unknown fallback %q", name, profile.Fallback)
			}
		}
	}
	for name := range catalog.Profiles {
		seen := map[string]bool{}
		current := name
		for current != "" {
			if seen[current] {
				return policy.Catalog{}, fmt.Errorf("profile fallback cycle at %q", current)
			}
			seen[current] = true
			current = catalog.Profiles[current].Fallback
		}
	}
	defaultProfile := decoded.DefaultProfile
	if defaultProfile == "" {
		defaultProfile = catalog.DefaultProfile
	}
	if _, exists := catalog.Profiles[defaultProfile]; !exists {
		return policy.Catalog{}, fmt.Errorf("unknown default profile %q", defaultProfile)
	}
	catalog.DefaultProfile = defaultProfile
	return catalog, nil
}

// Load reads an explicit or optional local configuration.
func Load(path string, explicit bool) (Result, error) {
	if path == "" {
		return Result{Catalog: policy.BuiltinCatalog()}, nil
	}
	data, err := os.ReadFile(filepath.Clean(path))
	if errors.Is(err, os.ErrNotExist) && !explicit {
		return Result{Catalog: policy.BuiltinCatalog()}, nil
	}
	if err != nil {
		return Result{}, err
	}
	decoded, err := decode(data)
	if err != nil {
		return Result{}, err
	}
	catalog, err := buildCatalog(decoded)
	if err != nil {
		return Result{}, err
	}
	hash := sha256.Sum256(data)
	return Result{Catalog: catalog, Hash: hex.EncodeToString(hash[:]), Source: "local"}, nil
}

// Path resolves CLI, environment, and repository-local configuration precedence.
func Path(cliPath string, environment map[string]string) (string, bool) {
	if cliPath != "" {
		return cliPath, true
	}
	if path := environment["RESOURCE_GUARD_CONFIG"]; path != "" {
		return path, true
	}
	if path := environment["RESOURCE_GUARD_DEFAULT_CONFIG"]; path != "" {
		return path, false
	}
	return filepath.Join("apps", "resource-guard", "resource-guard.local.json"), false
}
