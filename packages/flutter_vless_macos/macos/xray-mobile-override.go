package XRay

import (
	"bytes"
	"runtime/debug"
	"strings"

	_ "github.com/xtls/xray-core/main/distro/all"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
)

type Logger interface {
	LogInput(s string)
}

var coreInstance *core.Instance

func SetMemoryLimit() {
	debug.SetGCPercent(10)
	debug.SetMemoryLimit(30 * 1024 * 1024)
}

func Start(config []byte, logger Logger) error {
	conf, err := serial.DecodeJSONConfig(bytes.NewReader(config))
	if err != nil {
		logger.LogInput("Config load error: " + err.Error())
		return err
	}
	pbConfig, err := conf.Build()
	if err != nil {
		return err
	}
	instance, err := core.New(pbConfig)
	if err != nil {
		logger.LogInput("Create XRay error: " + err.Error())
		return err
	}
	err = instance.Start()
	if err != nil {
		logger.LogInput("Start XRay error: " + err.Error())
		return err
	}
	coreInstance = instance
	return nil
}

func Stop() {
	if coreInstance != nil {
		coreInstance.Close()
		coreInstance = nil
	}
}

func GetVersion() string {
	return core.Version()
}

func MeasureDelay(url string) (int64, error) {
	return 0, nil
}

func MeasureOutboundDelay(ConfigureFileContent string, url string) (int64, error) {
	return 0, nil
}

// QueryStats returns all traffic counters as "name>>>value\n" lines.
// Uses VisitCounters which is available in xray-core features/stats.Manager.
// Caller parses "uplink" and "downlink" from counter names.
func QueryStats(tag string) string {
	if coreInstance == nil {
		return ""
	}
	sm := coreInstance.GetFeature(stats.ManagerType())
	if sm == nil {
		return ""
	}
	manager, ok := sm.(stats.Manager)
	if !ok {
		return ""
	}

	var sb strings.Builder
	manager.VisitCounters(func(name string, counter stats.Counter) bool {
		if tag == "" || strings.Contains(name, tag) {
			sb.WriteString(name)
			sb.WriteString(">>>")
			sb.WriteString(itoa(counter.Value()))
			sb.WriteByte('\n')
		}
		return true // continue iteration
	})
	return sb.String()
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	negative := n < 0
	if negative {
		n = -n
	}
	buf := make([]byte, 20)
	pos := len(buf)
	for n > 0 {
		pos--
		buf[pos] = byte(n%10) + '0'
		n /= 10
	}
	if negative {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}
