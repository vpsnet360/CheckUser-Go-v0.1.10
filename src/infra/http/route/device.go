package route

import (
	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/infra/adapter"
	"github.com/vpsnet360/CheckUser-Go-v0.1.10/src/infra/factory"
	"github.com/labstack/echo/v4"
)

func CreateDeviceRoute(g *echo.Group) {
	g.GET("/devices/list", adapter.NewEchoAdapter(factory.MakeListDevicesHandler()).Adapt)
	g.GET("/devices/list/:username", adapter.NewEchoAdapter(factory.MakeListDevicesByUsernameHandler()).Adapt)
	g.GET("/devices/count", adapter.NewEchoAdapter(factory.MakeCountDevicesHandler()).Adapt)
}
