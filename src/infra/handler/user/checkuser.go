package user_handler

import (
	"context"
	"errors"

	user_use_case "github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/usecase/device"
	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/infra/handler"
)

type checkUserHandler struct {
	checkUserUseCase *user_use_case.CheckUserUseCase
}

func NewCheckUserHandler(checkUserUseCase *user_use_case.CheckUserUseCase) handler.Handler {
	return &checkUserHandler{checkUserUseCase}
}

func (h *checkUserHandler) Handle(ctx context.Context, request *handler.HttpRequest) (*handler.HttpResponse, error) {
	username := request.Query("username")
	deviceID := request.Query("deviceId")
	if username == "" || deviceID == "" {
		return nil, errors.New("Please provide a username and device ID")
	}

	output, err := h.checkUserUseCase.Execute(ctx, username, deviceID)
	if err != nil {
		return nil, err
	}

	return &handler.HttpResponse{
		Status: 200,
		Body:   output,
	}, nil
}
