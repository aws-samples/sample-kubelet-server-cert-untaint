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
	"math/rand"
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

// SleepJitter sleeps for a random duration in [0, max) before returning. In a
// DaemonSet, every pod starts at roughly the same instant during a scale-up,
// so without jitter N pods hit the apiserver in lockstep and trip
// priority-and-fairness throttling (HTTP 429). Spreading the first request over
// a small random window flattens that boot spike. A non-positive max is a no-op.
func SleepJitter(max time.Duration) {
	if max <= 0 {
		return
	}
	delay := time.Duration(rand.Int63n(int64(max)))
	klog.V(2).InfoS("Applying startup jitter before contacting apiserver", "delay", delay.String(), "max", max.String())
	time.Sleep(delay)
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
