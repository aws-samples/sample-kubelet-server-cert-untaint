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

package taint

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	k8stypes "k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"k8s.io/klog/v2"
)

type jsonPatch struct {
	OP    string `json:"op,omitempty"`
	Path  string `json:"path,omitempty"`
	Value any    `json:"value"`
}

func remove(ctx context.Context, clientset *kubernetes.Clientset, node *corev1.Node, taintKey string) error {
	var taintsToKeep []corev1.Taint

	for _, taint := range node.Spec.Taints {
		if taint.Key != taintKey {
			taintsToKeep = append(taintsToKeep, taint)
		} else {
			klog.V(4).InfoS("Queued taint for removal", "key", taint.Key, "effect", taint.Effect)
		}
	}

	if len(taintsToKeep) == len(node.Spec.Taints) {
		klog.V(4).InfoS("No taints to remove, skipping taint removal", "node", node.Name)
		return nil
	}

	patchRemoveTaints := []jsonPatch{
		{OP: "test", Path: "/spec/taints", Value: node.Spec.Taints},
		{OP: "replace", Path: "/spec/taints", Value: taintsToKeep},
	}

	patch, err := json.Marshal(patchRemoveTaints)
	if err != nil {
		return err
	}

	_, err = clientset.CoreV1().Nodes().Patch(ctx, node.Name, k8stypes.JSONPatchType, patch, metav1.PatchOptions{})
	if err != nil {
		return err
	}
	klog.V(4).InfoS("Removed taint from local node", "node", node.Name, "taint", taintKey)
	return nil
}

func hasTaint(n *corev1.Node, taintKey string) bool {
	for _, t := range n.Spec.Taints {
		if t.Key == taintKey {
			return true
		}
	}
	return false
}

func StartWatcher(clientset *kubernetes.Clientset, nodeName, taintKey string, maxWatchDuration time.Duration) {
	klog.V(2).InfoS("startNotReadyTaintWatcher - creating short-lived node informer", "node", nodeName, "maxWatchDuration", maxWatchDuration.String())

	factory := informers.NewSharedInformerFactoryWithOptions(
		clientset,
		5*time.Second,
		informers.WithTweakListOptions(func(lo *metav1.ListOptions) {
			lo.FieldSelector = "metadata.name=" + nodeName
		}),
	)
	informer := factory.Core().V1().Nodes().Informer()

	var mutex sync.Mutex
	ctx, cancel := context.WithTimeout(context.Background(), maxWatchDuration+10*time.Second)
	defer cancel()

	attemptTaintRemoval := func(n *corev1.Node) {
		if !hasTaint(n, taintKey) {
			klog.V(4).InfoS("Node has no taint, do nothing", "node", nodeName, "taint", taintKey)
			return
		}

		klog.V(4).InfoS("Node has taint, remove taint", "node", nodeName, "taint", taintKey)

		if !mutex.TryLock() {
			return
		}
		defer mutex.Unlock()

		backoff := wait.Backoff{Duration: 2 * time.Second, Factor: 1.5, Steps: 5}
		err := wait.ExponentialBackoffWithContext(ctx, backoff, func(ctx context.Context) (bool, error) {
			if err := remove(ctx, clientset, n, taintKey); err != nil {
				if apierrors.IsBadRequest(err) || apierrors.IsInvalid(err) || apierrors.IsNotFound(err) {
					freshNode, nodeErr := clientset.CoreV1().Nodes().Get(ctx, n.Name, metav1.GetOptions{})
					if nodeErr != nil {
						klog.ErrorS(nodeErr, "Failed to update potentially stale node", "node", n.Name)
						return false, nil
					}
					if !hasTaint(freshNode, taintKey) {
						return true, nil
					}
					n = freshNode
				}
				klog.ErrorS(err, "Failed to remove taint, retrying", "node", n.Name, "error", err)
				return false, nil
			}
			return true, nil
		})

		if err != nil {
			klog.ErrorS(err, "Timed out removing taint", "node", n.Name)
		}
	}

	if _, err := informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj any) {
			if n, ok := obj.(*corev1.Node); ok {
				attemptTaintRemoval(n)
			}
		},
		UpdateFunc: func(_, newObj any) {
			if n, ok := newObj.(*corev1.Node); ok {
				attemptTaintRemoval(n)
			}
		},
	}); err != nil {
		klog.ErrorS(err, "Taint‑watcher: Failed to add event handler")
		return
	}

	if err := informer.SetWatchErrorHandlerWithContext(func(handlerCtx context.Context, r *cache.Reflector, err error) {
		if apierrors.IsUnauthorized(err) || apierrors.IsForbidden(err) {
			klog.V(8).InfoS("Taint-watcher: permission error, silently cancelling context")
			cancel()
		} else {
			cache.DefaultWatchErrorHandler(handlerCtx, r, err)
		}
	}); err != nil {
		klog.ErrorS(err, "Taint‑watcher: Failed to add error handler")
		return
	}

	factory.Start(ctx.Done())
	if ok := cache.WaitForCacheSync(ctx.Done(), informer.HasSynced); !ok {
		if ctx.Err() != nil {
			klog.V(8).InfoS("Taint-watcher: cache sync cancelled (likely permissions error)")
		} else {
			klog.ErrorS(nil, "Taint-watcher: cache sync failed")
		}
	} else {
		if obj, exists, err := informer.GetStore().GetByKey(nodeName); err == nil && exists {
			if n, ok := obj.(*corev1.Node); ok {
				attemptTaintRemoval(n)
			}
		}

		<-time.After(maxWatchDuration)
		klog.V(8).InfoS("Taint-watcher: timeout reached; stopping")
	}

	lastChanceNode, err := clientset.CoreV1().Nodes().Get(ctx, nodeName, metav1.GetOptions{})
	if err != nil {
		klog.ErrorS(err, "Failed to get node for last chance taint removal", "node", nodeName)
	} else {
		attemptTaintRemoval(lastChanceNode)
	}
}
