package device_handler

import (
	"context"

	device_use_case "github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/usecase/device"
	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/infra/handler"
)

type countDevicesHandler struct {
	countDevicesUseCase *device_use_case.CountDevicesUseCase
}

func NewCountDevicesHandler(countDevicesUseCase *device_use_case.CountDevicesUseCase) handler.Handler {
	return &countDevicesHandler{countDevicesUseCase}
}

func (h *countDevicesHandler) Handle(ctx context.Context, request *handler.HttpRequest) (*handler.HttpResponse, error) {
	count, err := h.countDevicesUseCase.Execute(ctx)
	if err != nil {
		return nil, err
	}

	return &handler.HttpResponse{
		Status: 200,
		Body:   map[string]int{"count": count},
	}, nil
}
