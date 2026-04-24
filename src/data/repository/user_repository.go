package repository

import (
	"context"
	"time"

	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/contract"
	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/entity"
)

type systemUserRepository struct {
	userDAO          contract.UserDAO
	userCacheService contract.UserCacheService
}

func NewSystemUserRepository(userDAO contract.UserDAO, userCacheService contract.UserCacheService) contract.UserRepository {
	return &systemUserRepository{
		userDAO:          userDAO,
		userCacheService: userCacheService,
	}
}

func (r *systemUserRepository) FindByUsername(ctx context.Context, username string) (*entity.User, error) {
	user, found := r.userCacheService.Get(username)
	if found {
		return user, nil
	}

	user, err := r.userDAO.FindByUsername(ctx, username)
	if err != nil {
		return nil, err
	}

	r.userCacheService.Set(user, time.Minute*30)
	return user, nil
}
