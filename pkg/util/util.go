/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package util

import (
	"errors"
	"os"
	"os/signal"
	"syscall"
	"time"

	"k8s.io/klog/v2"
)

func FileExists(file string) bool {
	_, err := os.Stat(file)
	return !errors.Is(err, os.ErrNotExist)
}

func SetupSignalHandler() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	var terminationGracePeriodSeconds time.Duration = 5 * time.Second
	go func() {
		sig := <-sigChan
		klog.V(2).InfoS("Received signal, shutting down", "signal", sig.String(), "wait", terminationGracePeriodSeconds)
		time.Sleep(terminationGracePeriodSeconds)
		klog.V(2).InfoS("Exiting gracefully")
		klog.Flush()
		os.Exit(0)
	}()
}
