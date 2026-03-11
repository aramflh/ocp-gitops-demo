#!/usr/bin/env bash
#
# Idempotent setup script for Red Hat OpenShift GitOps.
# Installs the GitOps operator, waits for all components to be ready,
# then prints the Argo CD URL and admin credentials.
#
# Prerequisites: oc CLI, cluster admin (or sufficient privileges).
# Usage: ./scripts/setup-gitops.sh

set -euo pipefail

# Configurable timeouts and intervals
MAX_WAIT_OPERATOR="${MAX_WAIT_OPERATOR:-600}"      # seconds to wait for operator/CSV
MAX_WAIT_DEPLOYMENTS="${MAX_WAIT_DEPLOYMENTS:-600}" # seconds to wait for deployments
POLL_INTERVAL="${POLL_INTERVAL:-15}"

GITOPS_NS="openshift-gitops"
OPERATORS_NS="openshift-operators"
OPERATOR_NAME="openshift-gitops-operator"
SUBSCRIPTION_NAME="openshift-gitops-operator"
ROUTE_NAME="openshift-gitops-server"
SECRET_NAME="openshift-gitops-cluster"
ADMIN_USER="admin"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }

# --- Preflight ---
preflight() {
  if ! command -v oc &>/dev/null; then
    die "oc CLI not found. Install it and ensure it is on PATH."
  fi
  if ! oc whoami &>/dev/null; then
    die "Not logged in to OpenShift. Run 'oc login' first."
  fi
  log "Connected to cluster: $(oc whoami --show-server)"
}

# --- Get default channel for GitOps operator (idempotent) ---
get_channel() {
  local channel
  channel=$(oc get packagemanifests.packages.operators.coreos.com -n openshift-marketplace \
    openshift-gitops-operator -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
  if [[ -z "${channel}" ]]; then
    die "Could not get default channel for openshift-gitops-operator. Is the package available in openshift-marketplace?"
  fi
  echo "${channel}"
}

# --- Create Subscription (idempotent: oc apply) ---
apply_subscription() {
  local channel="$1"
  log "Creating/updating Subscription for OpenShift GitOps (channel: ${channel})..."
  cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUBSCRIPTION_NAME}
  namespace: ${OPERATORS_NS}
spec:
  channel: ${channel}
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  log "Subscription applied."
}

# --- Authorize GitOps ServiceAccount (idempotent: create only if missing) ---
ensure_cluster_role_binding() {
  if oc get clusterrolebinding gitops-scc-binding &>/dev/null; then
    log "ClusterRoleBinding gitops-scc-binding already exists; skipping."
    return 0
  fi
  log "Creating ClusterRoleBinding for GitOps ServiceAccount..."
  oc create clusterrolebinding gitops-scc-binding \
    --clusterrole cluster-admin \
    --serviceaccount "${GITOPS_NS}:openshift-gitops-argocd-application-controller"
  log "ClusterRoleBinding created."
}

# --- Wait for namespace (created by operator) ---
wait_for_namespace() {
  local waited=0
  until oc get namespace "${GITOPS_NS}" &>/dev/null; do
    if [[ ${waited} -ge ${MAX_WAIT_OPERATOR} ]]; then
      die "Timeout waiting for namespace ${GITOPS_NS}."
    fi
    log "Waiting for namespace ${GITOPS_NS}... (${waited}s)"
    sleep "${POLL_INTERVAL}"
    waited=$((waited + POLL_INTERVAL))
  done
  log "Namespace ${GITOPS_NS} exists."
}

# --- Wait for operator and CSV to be Succeeded ---
wait_for_operator_ready() {
  local waited=0
  log "Waiting for operator and CSV to be ready (up to ${MAX_WAIT_OPERATOR}s)..."
  while true; do
    if [[ ${waited} -ge ${MAX_WAIT_OPERATOR} ]]; then
      die "Timeout waiting for GitOps operator/CSV to be ready."
    fi
    if oc get operators "${OPERATOR_NAME}.${OPERATORS_NS}" &>/dev/null; then
      csv_status=$(oc get csv -n "${OPERATORS_NS}" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
      if echo "${csv_status}" | grep -q "Succeeded"; then
        log "Operator and CSV are ready."
        return 0
      fi
    fi
    log "Operator/CSV not ready yet... (${waited}s)"
    sleep "${POLL_INTERVAL}"
    waited=$((waited + POLL_INTERVAL))
  done
}

# --- Wait for all deployments in openshift-gitops to be READY ---
wait_for_deployments_ready() {
  local waited=0
  log "Waiting for all deployments in ${GITOPS_NS} to be ready (up to ${MAX_WAIT_DEPLOYMENTS}s)..."
  while true; do
    if [[ ${waited} -ge ${MAX_WAIT_DEPLOYMENTS} ]]; then
      die "Timeout waiting for deployments in ${GITOPS_NS} to be ready."
    fi
    # READY column is e.g. "1/1"; we need every deployment to have at least 1/1 (or N/N)
    not_ready=$(oc get deployment -n "${GITOPS_NS}" --no-headers 2>/dev/null | \
      awk '$2 !~ /^[1-9][0-9]*\/[1-9][0-9]*$/ {print $1}' || true)
    if [[ -z "${not_ready}" ]]; then
      count=$(oc get deployment -n "${GITOPS_NS}" --no-headers 2>/dev/null | wc -l)
      if [[ ${count} -gt 0 ]]; then
        log "All deployments in ${GITOPS_NS} are ready."
        return 0
      fi
    fi
    log "Deployments not all ready... (${waited}s)"
    sleep "${POLL_INTERVAL}"
    waited=$((waited + POLL_INTERVAL))
  done
}

# --- Get Argo CD URL from route ---
get_url() {
  local url
  url=$(oc get -n "${GITOPS_NS}" route "${ROUTE_NAME}" -o jsonpath='{.status.ingress[0].host}' 2>/dev/null || true)
  if [[ -z "${url}" ]]; then
    # Try alternate path (some versions use different structure)
    url=$(oc get -n "${GITOPS_NS}" route "${ROUTE_NAME}" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  fi
  if [[ -z "${url}" ]]; then
    die "Could not get route host for ${ROUTE_NAME} in ${GITOPS_NS}."
  fi
  # Ensure scheme
  if [[ ! "${url}" =~ ^https?:// ]]; then
    url="https://${url}"
  fi
  echo "${url}"
}

# --- Get admin password from secret ---
get_admin_password() {
  local pass
  pass=$(oc get -n "${GITOPS_NS}" secret "${SECRET_NAME}" -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -z "${pass}" ]]; then
    die "Could not get admin password from secret ${SECRET_NAME} in ${GITOPS_NS}."
  fi
  echo "${pass}"
}

# --- Print summary with URL and credentials ---
print_summary() {
  local url password
  url=$(get_url)
  password=$(get_admin_password)
  echo ""
  echo "=============================================="
  echo "  OpenShift GitOps (Argo CD) is ready"
  echo "=============================================="
  echo ""
  echo "  URL:      ${url}"
  echo "  Username: ${ADMIN_USER}"
  echo "  Password: ${password}"
  echo ""
  echo "  Open the URL in a browser and log in with the credentials above."
  echo "=============================================="
  echo ""
}

# --- Main ---
main() {
  log "Starting OpenShift GitOps setup (idempotent)."
  preflight
  channel=$(get_channel)
  apply_subscription "${channel}"
  wait_for_namespace
  ensure_cluster_role_binding
  wait_for_operator_ready
  wait_for_deployments_ready
  print_summary
  log "Done."
}

main "$@"
