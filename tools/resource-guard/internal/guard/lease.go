package guard

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"syscall"
	"time"
)

type leaseOwner struct {
	SchemaVersion int    `json:"schemaVersion"`
	PID           int    `json:"pid"`
	Token         string `json:"token,omitempty"`
	Port          int    `json:"port,omitempty"`
	Owner         string `json:"owner,omitempty"`
}
type Session struct {
	Inherited   bool
	Path, Token string
}
type PortLease struct {
	Path, Owner string
	Port        int
}

func livePID(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}
func readLeaseOwner(path string) (*leaseOwner, error) {
	data, err := os.ReadFile(filepath.Join(path, "owner.json"))
	if err != nil {
		return nil, err
	}
	var owner leaseOwner
	if err = json.Unmarshal(data, &owner); err != nil {
		return nil, err
	}
	return &owner, nil
}
func writeLeaseOwner(path string, owner leaseOwner) error {
	data, err := json.Marshal(owner)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(path, "owner.json"), append(data, '\n'), 0o600)
}
func token() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func InheritedSession(root, candidate string) bool {
	if candidate == "" {
		return false
	}
	owner, err := readLeaseOwner(filepath.Join(root, "heavy.lock"))
	return err == nil && owner.SchemaVersion == 1 && owner.Token == candidate && livePID(owner.PID)
}

func AcquireSession(root, inheritedToken string, wait time.Duration, pause func(time.Duration)) (*Session, error) {
	if InheritedSession(root, inheritedToken) {
		return &Session{Inherited: true, Token: inheritedToken}, nil
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, err
	}
	lockPath := filepath.Join(root, "heavy.lock")
	deadline := time.Now().Add(wait)
	for !time.Now().After(deadline) {
		if err := os.Mkdir(lockPath, 0o700); err == nil {
			value, tokenError := token()
			if tokenError != nil {
				_ = os.Remove(lockPath)
				return nil, tokenError
			}
			if writeError := writeLeaseOwner(lockPath, leaseOwner{SchemaVersion: 1, PID: os.Getpid(), Token: value}); writeError != nil {
				_ = os.RemoveAll(lockPath)
				return nil, writeError
			}
			return &Session{Path: lockPath, Token: value}, nil
		} else if !errors.Is(err, os.ErrExist) {
			return nil, err
		}
		owner, ownerError := readLeaseOwner(lockPath)
		if ownerError == nil && !livePID(owner.PID) {
			if err := os.RemoveAll(lockPath); err != nil {
				return nil, err
			}
			continue
		}
		pause(time.Second)
	}
	return nil, nil
}

func ReleaseSession(root string, session *Session) error {
	if session == nil || session.Inherited {
		return nil
	}
	expected := filepath.Join(root, "heavy.lock")
	if session.Path != expected {
		return errors.New("refusing to release an invalid resource session")
	}
	owner, err := readLeaseOwner(expected)
	if err != nil {
		return err
	}
	if owner.PID != os.Getpid() || owner.Token != session.Token {
		return errors.New("refusing to release a resource session owned by another process")
	}
	return os.RemoveAll(expected)
}

var portOwnerPattern = regexp.MustCompile(`^[a-z0-9-]+$`)

func AcquirePortLease(root string, port int, ownerName string, minimum, maximum int) (*PortLease, error) {
	if port < minimum || port > maximum {
		return nil, fmt.Errorf("port must be between %d and %d", minimum, maximum)
	}
	if !portOwnerPattern.MatchString(ownerName) {
		return nil, errors.New("port lease owner is invalid")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, err
	}
	path := filepath.Join(root, fmt.Sprintf("%d.lock", port))
	for attempt := 0; attempt < 2; attempt++ {
		if err := os.Mkdir(path, 0o700); err == nil {
			if writeError := writeLeaseOwner(path, leaseOwner{SchemaVersion: 1, PID: os.Getpid(), Port: port, Owner: ownerName}); writeError != nil {
				_ = os.RemoveAll(path)
				return nil, writeError
			}
			return &PortLease{Path: path, Port: port, Owner: ownerName}, nil
		} else if !errors.Is(err, os.ErrExist) {
			return nil, err
		}
		marker, markerError := readLeaseOwner(path)
		if markerError != nil || marker.SchemaVersion != 1 || marker.Port != port || livePID(marker.PID) {
			return nil, fmt.Errorf("port %d is already leased", port)
		}
		if err := os.RemoveAll(path); err != nil {
			return nil, err
		}
	}
	return nil, fmt.Errorf("port %d could not be leased", port)
}

func ReleasePortLease(root string, lease *PortLease) error {
	if lease == nil {
		return nil
	}
	expected := filepath.Join(root, fmt.Sprintf("%d.lock", lease.Port))
	if lease.Path != expected {
		return errors.New("refusing to release an invalid port lease")
	}
	owner, err := readLeaseOwner(expected)
	if err != nil {
		return err
	}
	if owner.PID != os.Getpid() || owner.Port != lease.Port || owner.Owner != lease.Owner {
		return errors.New("refusing to release a port lease owned by another process")
	}
	return os.RemoveAll(expected)
}
