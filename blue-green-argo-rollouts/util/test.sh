#!/usr/bin/env bash
rm -rf /tmp/deployment
mkdir /tmp/deployment
cd /tmp/deployment

git clone https://github.com/davidseve/cloud-native-deployment-strategies.git
cd cloud-native-deployment-strategies
#To work with a branch that is not main. ./test.sh no helm_base
if [ ${2:-no} != "no" ]
then
    git checkout $2
fi
git checkout -b rollouts
git push origin rollouts

oc apply -f gitops/gitops-operator.yaml

#First time we install operators take logger
if [ ${1:-no} = "no" ]
then
    sleep 30s
else
    sleep 1m
fi

#To work with a branch that is not main. ./test.sh no helm_base
if [ ${2:-no} != "no" ]
then
    sed -i "s/HEAD/$2/g" blue-green-argo-rollouts/application-cluster-config.yaml
fi

sed -i '/pipeline.enabled/{n;s/.*/        value: "true"/}' blue-green-argo-rollouts/application-cluster-config.yaml
oc apply -f blue-green-argo-rollouts/application-cluster-config.yaml --wait=true

#First time we install operators take logger
if [ ${1:-no} = "no" ]
then
    sleep 1m
else
    sleep 2m
fi

sed -i 's/change_me/davidseve/g' blue-green-argo-rollouts/application-shop-blue-green-rollouts.yaml

oc apply -f blue-green-argo-rollouts/application-shop-blue-green-rollouts.yaml --wait=true
tkn pipeline start pipeline-blue-green-e2e-test --param NEW_IMAGE_TAG=v1.0.1 --param MODE=online --param LABEL=.version --param APP=products --param NAMESPACE=gitops --param MESH=False --param JQ_PATH=.metadata --workspace name=app-source,claimName=workspace-pvc-shop-cd-e2e-tests -n gitops --showlog

sed -i '/products-blue/{n;n;n;n;s/.*/      tag: v1.1.1/}' helm/quarkus-helm-umbrella/chart/values/values-rollouts.yaml

git add helm/quarkus-helm-umbrella/chart/values/values-rollouts.yaml
git commit -m "Change products version to v1.1.1"
git push origin rollouts

status=none
while [[ "$status" != "Paused - BlueGreenPause" ]]
do
    sleep 5
    status=$(kubectlArgo argo rollouts status products -n gitops  --watch=false)
    echo $status
done

tkn pipeline start pipeline-blue-green-e2e-test --param NEW_IMAGE_TAG=v1.1.1 --param MODE=offline --param LABEL=.version --param APP=products --param NAMESPACE=gitops --param MESH=False --param JQ_PATH=.metadata --workspace name=app-source,claimName=workspace-pvc-shop-cd-e2e-tests -n gitops --showlog

oc project gitops
kubectlArgo argo rollouts promote products -n gitops

tkn pipeline start pipeline-blue-green-e2e-test --param NEW_IMAGE_TAG=v1.1.1 --param MODE=online --param LABEL=.version --param APP=products --param NAMESPACE=gitops --param MESH=False --param JQ_PATH=.metadata --workspace name=app-source,claimName=workspace-pvc-shop-cd-e2e-tests -n gitops --showlog

#Rollback
#this is not neccesary becase argo rollouts do the rollback because of scaleDownDelaySeconds (default 30 seconds), just to make it work I add the sleep
sleep 10
git revert HEAD --no-edit
git push origin rollouts

status=none
while [[ "$status" != "Paused - BlueGreenPause" ]]
do
    sleep 5
    status=$(kubectlArgo argo rollouts status products -n gitops  --watch=false)
    echo $status
done
kubectlArgo argo rollouts promote products -n gitops

tkn pipeline start pipeline-blue-green-e2e-test --param NEW_IMAGE_TAG=v1.0.1 --param MODE=online --param LABEL=.version --param APP=products --param NAMESPACE=gitops --param MESH=False --param JQ_PATH=.metadata --workspace name=app-source,claimName=workspace-pvc-shop-cd-e2e-tests -n gitops --showlog
