//go:build darwin || linux

package host

import (
	"errors"
	"math"

	"golang.org/x/sys/unix"
)

func diskCapacity(path string) (*int64, *int64, error) {
	var value unix.Statfs_t
	if err := unix.Statfs(path, &value); err != nil {
		return nil, nil, err
	}
	if value.Bsize <= 0 {
		return nil, nil, errors.New("disk block size is invalid")
	}
	blockSize := uint64(value.Bsize)
	if value.Bavail > math.MaxInt64/blockSize || value.Blocks > math.MaxInt64/blockSize {
		return nil, nil, errors.New("disk capacity exceeds supported range")
	}
	free := int64(value.Bavail * blockSize)  //nolint:gosec // Multiplication is bounded above by math.MaxInt64.
	total := int64(value.Blocks * blockSize) //nolint:gosec // Multiplication is bounded above by math.MaxInt64.
	return &free, &total, nil
}
