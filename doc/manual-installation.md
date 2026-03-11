# Manual installation of OpenShift GitOps

This document describes the manual steps to install the OpenShift GitOps Operator and obtain the Argo CD URL and credentials. Use this if you prefer not to use the [setup script](../scripts/setup-gitops.sh) or need to troubleshoot.

## Install GitOps Operator

### Find out the channel to be used

```bash
oc get packagemanifests.packages.operators.coreos.com -n openshift-marketplace openshift-gitops-operator -o jsonpath='{.status.defaultChannel}{"\n"}'
```

The output should show one or more values, like:

> **latest**

### Create the subscription

Using this channel value, create the subscription manifest for installing the OpenShift GitOps Operator. The default namespace `openshift-operators` can be used, as the GitOps operator supports all namespaces as targets.

Replace `latest` in `channel: latest` with the channel value from the previous step if different.

```bash
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Authorizing GitOps ServiceAccount

Upon installation, the OpenShift GitOps Operator creates the namespace `openshift-gitops` and a service account `openshift-gitops-argocd-application-controller` in that namespace. This service account is used to apply manifests on the cluster. It has sufficient privileges in `openshift-gitops` but not in other namespaces.

To allow creating resources across the cluster for this lab, grant this service account cluster-admin:

> **NOTE:** In a production environment, you may need to be more restrictive about the role and namespaces you give this service account.

```bash
oc create clusterrolebinding gitops-scc-binding --clusterrole cluster-admin --serviceaccount openshift-gitops:openshift-gitops-argocd-application-controller
```

### Verify the operator is installed

Ensure the operator installation is accepted and successful:

```bash
oc get operators openshift-gitops-operator.openshift-operators
oc get csv -n openshift-operators | grep gitops
```

The CSV should show phase **Succeeded**.

Verify that all deployments in `openshift-gitops` are running:

```bash
oc get deployment -n openshift-gitops
```

Example output:

```
NAME                                         READY   UP-TO-DATE   AVAILABLE   AGE
cluster                                      1/1     1            1           8m10s
kam                                          1/1     1            1           8m10s
openshift-gitops-applicationset-controller   1/1     1            1           8m7s
openshift-gitops-dex-server                  1/1     1            1           8m10s
openshift-gitops-redis                       1/1     1            1           8m8s
openshift-gitops-repo-server                 1/1     1            1           8m8s
openshift-gitops-server                      1/1     1            1           8m7s
```

## Accessing the GitOps Operator GUI

### Get the route (URL)

```bash
oc get -n openshift-gitops routes openshift-gitops-server -o jsonpath='{.status.ingress[].host}{"\n"}'
```

Example output: `openshift-gitops-server-openshift-gitops.apps.cluster-jl57k.dynamic.redhatworkshops.io`

Use `https://<that-host>` in your browser.

### Get the admin password

Default username is `admin`. To retrieve the password:

```bash
oc get -n openshift-gitops secrets openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d ; echo
```

### Argo CD GUI

Open the URL in a browser and log in with username `admin` and the password from above.
