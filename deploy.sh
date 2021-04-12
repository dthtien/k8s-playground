#!/bin/sh -ex
export KUBECONFIG=~/.kube/main-app.yaml
docker build -t dthtien/k8s-playaround:latest .
docker push dthtien/k8s-playaround:latest
kubectl create -f config/kube/migrate.yml
kubectl wait --for=condition=complete --timeout=600s job/migrate
kubectl delete job migrate
# kubectl delete pods -l app=rails-app
# kubectl delete pods -l app=sidekiq
# For Kubernetes >= 1.15 replace the last two lines with the following
# in order to have rolling restarts without downtime
kubectl rollout restart deployment/k8s-playaround-deployment
kubectl rollout restart deployment/sidekiq
