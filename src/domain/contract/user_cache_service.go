package contract

import (
	"time"

	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/entity"
)

type UserCacheService interface {
	Set(value *entity.User, ttl time.Duration)
	Get(username string) (*entity.User, bool)
}
