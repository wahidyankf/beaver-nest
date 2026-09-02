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
	"strings"
	"syscall"
	"time"
)

type leaseOwner struct {
	SchemaVersion int    `json:"schemaVersion"`
	PID           int    `json:"pid"`
	Token         string `json:"token,omitempty"`
	Port          int    `json:"port,omitempty"`
	Owner         string `json:"owner,omitempty"`
	Class         string `json:"class,omitempty"`
}

// Session identifies an owned or inherited guarded session.
type Session struct {
	Inherited   bool
	Path, Token string
	RecordPath  string
}

// Task classes understood by the guard.
const (
	ClassEphemeral     = "ephemeral"
	ClassService       = "service"
	ClassTransactional = "transactional"
)

// SerializesHeavyWork reports whether class competes for the single heavy-work lease.
// Long-lived services stay outside that lease so they never starve guarded gates.
func SerializesHeavyWork(class string) bool { return class != ClassService }

// PortLease identifies ownership of one bounded service port.
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

var sessionTokenPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)

func sessionRecordPath(root, sessionToken string) (string, bool) {
	if !sessionTokenPattern.MatchString(sessionToken) {
		return "", false
	}
	return filepath.Join(root, "sessions", sessionToken+".json"), true
}

func readSessionRecord(root, sessionToken string) (*leaseOwner, error) {
	path, valid := sessionRecordPath(root, sessionToken)
	if !valid {
		return nil, errors.New("invalid resource session token")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var owner leaseOwner
	if err = json.Unmarshal(data, &owner); err != nil {
		return nil, err
	}
	return &owner, nil
}

func writeSessionRecord(root string, owner leaseOwner) (string, error) {
	path, valid := sessionRecordPath(root, owner.Token)
	if !valid {
		return "", errors.New("invalid resource session token")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", err
	}
	data, err := json.Marshal(owner)
	if err != nil {
		return "", err
	}
	if err = os.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		return "", err
	}
	return path, nil
}

// pruneSessionRecords removes records whose owning process is gone.
func pruneSessionRecords(root string) {
	directory := filepath.Join(root, "sessions")
	entries, err := os.ReadDir(directory)
	if err != nil {
		return
	}
	for _, entry := range entries {
		recordToken := strings.TrimSuffix(entry.Name(), ".json")
		owner, readError := readSessionRecord(root, recordToken)
		if readError != nil || !livePID(owner.PID) {
			_ = os.Remove(filepath.Join(directory, entry.Name()))
		}
	}
}

// InheritedSession reports whether candidate belongs to a live guarded owner.
func InheritedSession(root, candidate string) bool {
	if candidate == "" {
		return false
	}
	if owner, err := readSessionRecord(root, candidate); err == nil &&
		owner.SchemaVersion == 1 && owner.Token == candidate && livePID(owner.PID) {
		return true
	}
	owner, err := readLeaseOwner(filepath.Join(root, "heavy.lock"))
	return err == nil && owner.SchemaVersion == 1 && owner.Token == candidate && livePID(owner.PID)
}

// DescribeHeavyLease explains who holds the heavy-work lease, for actionable deferrals.
func DescribeHeavyLease(root string) string {
	owner, err := readLeaseOwner(filepath.Join(root, "heavy.lock"))
	if err != nil || !livePID(owner.PID) {
		return "the heavy-work lease reports no live owner"
	}
	class := owner.Class
	if class == "" {
		class = "unknown"
	}
	return fmt.Sprintf("the heavy-work lease is held by pid %d (class %s)", owner.PID, class)
}

// AcquireSession obtains a guarded session, returning nil after the lease wait expires.
// Heavy classes serialize on one lease; services record an inheritable session only.
func AcquireSession(root, inheritedToken, class string, wait time.Duration, pause func(time.Duration)) (*Session, error) {
	if InheritedSession(root, inheritedToken) {
		return &Session{Inherited: true, Token: inheritedToken}, nil
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, err
	}
	pruneSessionRecords(root)
	if !SerializesHeavyWork(class) {
		return registerSession(root, "", class)
	}
	lockPath := filepath.Join(root, "heavy.lock")
	deadline := time.Now().Add(wait)
	for !time.Now().After(deadline) {
		if err := os.Mkdir(lockPath, 0o700); err == nil {
			session, registerError := registerSession(root, lockPath, class)
			if registerError != nil {
				_ = os.RemoveAll(lockPath)
				return nil, registerError
			}
			return session, nil
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

// registerSession mints one session, recording it on the heavy lease when lockPath is set.
func registerSession(root, lockPath, class string) (*Session, error) {
	value, tokenError := token()
	if tokenError != nil {
		return nil, tokenError
	}
	owner := leaseOwner{SchemaVersion: 1, PID: os.Getpid(), Token: value, Class: class}
	if lockPath != "" {
		if writeError := writeLeaseOwner(lockPath, owner); writeError != nil {
			return nil, writeError
		}
	}
	recordPath, recordError := writeSessionRecord(root, owner)
	if recordError != nil {
		return nil, recordError
	}
	return &Session{Path: lockPath, Token: value, RecordPath: recordPath}, nil
}

// ReleaseSession removes only the session record and heavy-work lease owned by session.
func ReleaseSession(root string, session *Session) error {
	if session == nil || session.Inherited {
		return nil
	}
	if session.RecordPath != "" {
		expectedRecord, valid := sessionRecordPath(root, session.Token)
		if !valid || session.RecordPath != expectedRecord {
			return errors.New("refusing to release an invalid resource session")
		}
		if err := os.Remove(session.RecordPath); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	if session.Path == "" {
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

// AcquirePortLease obtains one validated port lease and reclaims a stale owner once.
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
	for range 2 {
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

// ReleasePortLease removes only the port marker owned by lease.
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
