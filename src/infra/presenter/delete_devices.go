package presenter

import (
	"context"
	"log"

	device_use_case "github.com/vpsnet360/CheckUser-Go-v0.1.10/src/domain/usecase/device"
)

type DeleteDevicesPresenter struct {
	deleteDevicesByUsername *device_use_case.DeleteDevicesByUsername
}

func NewDeleteDevicesPresenter(deleteDevicesByUsername *device_use_case.DeleteDevicesByUsername) *DeleteDevicesPresenter {
	return &DeleteDevicesPresenter{
		deleteDevicesByUsername: deleteDevicesByUsername,
	}
}

func (p *DeleteDevicesPresenter) Present(ctx context.Context, username string) {
	err := p.deleteDevicesByUsername.Execute(ctx, username)
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	log.Printf("Deleted devices for user %s", username)
}
