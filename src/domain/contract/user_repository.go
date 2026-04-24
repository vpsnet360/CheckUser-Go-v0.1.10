package contract

import (
	"context"

	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/entity"
)

type UserRepository interface {
	FindByUsername(ctx context.Context, username string) (*entity.User, error)
}
