#!/bin/bash

# Function to dump from Postgres 10 and restore to Bitnami Postgres 14
migrate_postgres_10_to_14() {
  local cluster_context=$1
  local namespace=$2

  if [ -z "$cluster_context" ] || [ -z "$namespace" ]; then
    echo "Error: Kubernetes context and namespace must be provided."
    echo "Usage: $0 <kube_context> <namespace>"
    return 1
  fi

  echo "Using Kubernetes context: $cluster_context"
  kubectl config use-context "$cluster_context"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to set Kubernetes context to '$cluster_context'. Aborting."
    return 1
  fi

  echo "--------------------------------------------------"
  echo "Starting migration for namespace: $namespace"
  echo "--------------------------------------------------"

  local dump_file="dump-${namespace}-$(date +%Y%m%d%H%M%S).sql"
  local pod_name="db-0" # Assuming the pod name remains db-0

  # --- Step 1: Dump from old Postgres 10 pod ---
  echo "Step 1: Dumping database from old pod ($pod_name) in namespace '$namespace'..."
  kubectl config set-context --current --namespace "$namespace"
  # Using /usr/local/bin/pg_dump which is common in older images
  kubectl exec "$pod_name" -- /usr/local/bin/pg_dump -U postgres -d proteam -f dump.sql
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to dump database from $pod_name in $namespace. Aborting."
    return 1
  fi
  echo "Dump command executed. Verifying dump file..."
  kubectl exec "$pod_name" -- tail dump.sql
  echo "Copying dump file locally to '$dump_file'..."
  kubectl cp --retries 10 "$pod_name":dump.sql "$dump_file"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to copy dump file from $pod_name in $namespace. Aborting."
    rm -f "$dump_file" # Clean up partial file if copy failed
    return 1
  fi
  echo "Dump file '$dump_file' created locally."
  # Optional: Remove dump from pod after copying
  # kubectl exec "$pod_name" -- rm dump.sql

  # --- Step 2: Upgrade Postgres Pod ---
  echo ""
  read -rp "Do you want to attempt an automated Helm upgrade? (yes/no): " auto_upgrade_choice

  if [[ "$auto_upgrade_choice" == "yes" ]]; then
    echo "Automated Helm upgrade selected."
    read -rp "Enter the Helm release name: " helm_release_name
    read -rp "Enter the Helm chart path or name (e.g., protopie/cloud or ./charts/cloud): " helm_chart_ref
    read -rp "Enter the target Helm chart version (optional, press Enter to use latest): " helm_chart_version
    read -rp "Enter the path to a custom Helm values file (optional, press Enter to skip): " helm_values_file

    if [ -z "$helm_release_name" ] || [ -z "$helm_chart_ref" ]; then
      echo "ERROR: Helm release name and chart reference are required for automated upgrade. Aborting."
      echo "Local dump file '$dump_file' is kept."
      return 1
    fi

    local helm_version_flag=""
    if [ -n "$helm_chart_version" ]; then
      helm_version_flag="--version $helm_chart_version"
    fi

    local helm_values_flag=""
    if [ -n "$helm_values_file" ]; then
      if [ -f "$helm_values_file" ]; then
        helm_values_flag="--values $helm_values_file"
        echo "Using custom Helm values file: $helm_values_file"
      else
        echo "WARNING: Custom Helm values file '$helm_values_file' not found. Proceeding without it."
      fi
    fi

    echo "Attempting automated upgrade for release '$helm_release_name' in namespace '$namespace' using chart '$helm_chart_ref' $helm_version_flag $helm_values_flag..."

    # Delete existing StatefulSet and PVC to ensure clean upgrade
    # Assuming StatefulSet is named 'db' and PVC follows 'data-<sts-name>-<pod-index>'
    local statefulset_name="db"
    local pvc_name="data-${statefulset_name}-0"
    local pv_name="" # Initialize pv_name

    echo "Attempting to identify PV for PVC '$pvc_name' in namespace '$namespace'..."
    # Try to get the PV name. Suppress error if PVC doesn't exist or not bound.
    # $? will be 0 if 'kubectl get' succeeds, even if .spec.volumeName is empty (e.g. PVC is Pending)
    pv_name=$(kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$pv_name" ]; then # Successfully got a PV name
      echo "PVC '$pvc_name' in namespace '$namespace' is bound to PV '$pv_name'."
    else
      # This case covers: PVC doesn't exist, PVC exists but is not bound, or kubectl command error
      echo "PVC '$pvc_name' not found in namespace '$namespace', or it is not bound to a PV. No specific PV to target for deletion later."
      pv_name="" # Ensure pv_name is empty
    fi

    echo "Deleting existing StatefulSet '$statefulset_name'..."
    kubectl delete statefulset "$statefulset_name" -n "$namespace" --ignore-not-found=true
    if [ $? -ne 0 ]; then
      echo "WARNING: Failed to delete StatefulSet '$statefulset_name'. Proceeding with Helm upgrade, but issues might occur."
    fi

    echo "Deleting existing PVC '$pvc_name'..."
    kubectl delete pvc "$pvc_name" -n "$namespace" --ignore-not-found=true
    if [ $? -ne 0 ]; then
      echo "WARNING: Command to delete PVC '$pvc_name' in namespace '$namespace' failed. Proceeding with Helm upgrade, but issues might occur."
    fi

    # Patch the identified PV to prevent re-binding and ensure it's retained
    if [ -n "$pv_name" ]; then
      echo "Attempting to patch PV '$pv_name' to prevent re-binding and ensure it is retained."

      # 1. Set persistentVolumeReclaimPolicy to Retain
      echo "Patching PV '$pv_name': setting persistentVolumeReclaimPolicy to Retain..."
      kubectl patch pv "$pv_name" --type merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
      if [ $? -ne 0 ]; then
        echo "WARNING: Failed to patch PV '$pv_name' to set persistentVolumeReclaimPolicy to Retain. Manual intervention may be needed for this PV."
      else
        echo "PV '$pv_name' reclaim policy set to Retain."
      fi

      # 2. Clear the claimRef to make the PV Available (but unlinked from the deleted PVC)
      # This changes the PV's status from Bound (to the now-deleted PVC) to Available.
      echo "Patching PV '$pv_name': clearing claimRef..."
      kubectl patch pv "$pv_name" --type merge -p '{"spec":{"claimRef":null}}'
      if [ $? -ne 0 ]; then
        echo "WARNING: Failed to patch PV '$pv_name' to clear claimRef. The PV might not become 'Available' as expected."
      else
        echo "PV '$pv_name' claimRef cleared. PV should now be 'Available'."
      fi

      # 3. Change storageClassName to a dummy value to prevent new PVCs from binding to it
      # This makes the PV unattractive for new PVCs requesting a standard storage class.
      local dummy_storage_class="old-retained-pv-${namespace}-$(date +%Y%m%d%H%M%S)"
      echo "Patching PV '$pv_name': setting storageClassName to '$dummy_storage_class'..."
      kubectl patch pv "$pv_name" --type merge -p "{\"spec\":{\"storageClassName\":\"${dummy_storage_class}\"}}"
      if [ $? -ne 0 ]; then
        echo "WARNING: Failed to patch PV '$pv_name' to set storageClassName to '$dummy_storage_class'. New PVCs might inadvertently bind to this PV if other conditions match."
      else
        echo "PV '$pv_name' storageClassName set to '$dummy_storage_class'."
      fi

      echo "PV '$pv_name' has been patched. It is set to be retained and should not be automatically re-bound by new PVCs requesting standard storage classes. Manual cleanup of this PV can be performed later."
      echo "If you want to delete this old PV, you can run following command after this scripts completion:"
      echo "      kubectl delte pv $pv_name"
    else
      echo "No specific PV was pre-identified for patching (e.g., PVC was not found, was unbound, or an error occurred retrieving PV name). Skipping PV patching."
    fi
    # Add a small delay to allow resources to terminate
    echo "Waiting for 10 seconds for resources to terminate..."
    sleep 10

    echo "Running Helm upgrade..."
    helm upgrade --install "$helm_release_name" "$helm_chart_ref" \
      --namespace "$namespace" \
      "$helm_version_flag" \
      "$helm_values_flag" \
      --wait --timeout 10m # Wait for deployment to complete

    if [ $? -ne 0 ]; then
      echo "ERROR: Helm upgrade failed for release '$helm_release_name'. Aborting."
      echo "Local dump file '$dump_file' is kept."
      return 1
    fi
    echo "Helm upgrade completed successfully."

  else
    # In this manual step, I think it would be better to user can whether choose the script runs
    # deleting all statefulsets in namespace and
    echo "Manual pod replacement selected."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "ACTION REQUIRED:"
    echo "1. Please MANUALLY delete the old '$pod_name' pod (and likely its StatefulSet/Deployment and PVC) in namespace '$namespace'."
    echo "   Example: kubectl delete statefulset db -n $namespace"
    echo "   Example: kubectl delete pvc data-db-0 -n $namespace"
    echo "2. Deploy the new Bitnami Postgres 14 resources (e.g., via Helm install/upgrade)."
    echo "3. Wait for the new pod '$pod_name' to be RUNNING."
    echo "   kubectl get pod $pod_name -n $namespace -w"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    read -rp "Once the NEW '$pod_name' pod is RUNNING, type 'continue' and press [Enter]: " user_input

    if [[ "$user_input" != "continue" ]]; then
      echo "Aborting migration for $namespace. Local dump file '$dump_file' is kept."
      return 1
    fi
  fi

  # --- Step 3: Restore to new Bitnami Postgres 14 pod ---
  echo "Step 3: Restoring database to new pod ($pod_name) in namespace '$namespace'..."
  kubectl config set-context --current --namespace "$namespace"

  # Wait for the new pod to be fully ready
  echo "Waiting for the new pod '$pod_name' in namespace '$namespace' to be Ready..."
  kubectl wait --for=condition=Ready pod/$pod_name -n "$namespace" --timeout=300s
  if [ $? -ne 0 ]; then
    echo "ERROR: Timed out waiting for pod '$pod_name' to become Ready. Aborting restore."
    echo "Local dump file '$dump_file' is kept."
    return 1
  fi
  sleep 10 # wait for in case of intializing init-db script
  echo "Pod '$pod_name' is Ready."

  # Prepare the new database (ensure schema exists, drop old tables)
  # Note: Bitnami uses POSTGRESQL_PASSWORD env var
  echo "Preparing target database (creating schema if not exists)..."
  kubectl exec "$pod_name" -- sh -c 'env PGPASSWORD=$POSTGRESQL_PASSWORD psql -U postgres -d proteam -c "CREATE SCHEMA IF NOT EXISTS public;"'
  if [ $? -ne 0 ]; then
    echo "WARNING: Failed to create schema. Restore might fail if schema doesn't exist."
  fi

  echo "Preparing target database (dropping existing public tables)..."
  kubectl exec "$pod_name" -- sh -c 'env PGPASSWORD=$POSTGRESQL_PASSWORD psql -U postgres -d proteam -c "DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = '\''public'\'') LOOP EXECUTE '\''DROP TABLE IF EXISTS public.'\'' || quote_ident(r.tablename) || '\'' CASCADE'\''; END LOOP; END \$\$;"'
  if [ $? -ne 0 ]; then
    echo "WARNING: Failed to drop tables. Restore might fail if tables already exist."
  fi

  echo "Restoring from local dump file '$dump_file'..."
  cat "$dump_file" | kubectl exec --stdin "$pod_name" -- sh -c 'env PGPASSWORD=$POSTGRESQL_PASSWORD psql -U postgres -d proteam'
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to restore database to $pod_name in $namespace automatically."
    echo "The local dump file '$dump_file' has been kept."
    echo "To restore manually, you can try the following steps:"
    echo "1. Copy the dump file to the new pod:"
    echo "   kubectl cp \"$dump_file\" \"${namespace}/${pod_name}:/tmp/restore_dump.sql\""
    echo "2. Execute psql in the pod to restore from the file:"
    echo "   kubectl exec -it \"${namespace}/${pod_name}\" -- sh -c 'env PGPASSWORD=\$POSTGRESQL_PASSWORD psql -U postgres -d proteam -f /tmp/restore_dump.sql'"
    echo "3. (Optional) After successful restore, remove the dump file from the pod:"
    echo "   kubectl exec \"${namespace}/${pod_name}\" -- rm /tmp/restore_dump.sql"
    echo "Aborting script. Please attempt manual restore."
    return 1
  fi

  echo "Restore complete for $namespace."

  # --- Step 4: Cleanup ---
  echo "Step 4: Cleaning up local dump file..."
  rm -f "$dump_file"
  echo "Local dump file '$dump_file' removed."

  echo "--------------------------------------------------"
  echo "Successfully completed migration for namespace: $namespace"
  echo "--------------------------------------------------"
  echo # Add a blank line for readability

  return 0
}

# --- Script Main Execution ---

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <kube_context> <namespace>"
  exit 1
fi

KUBE_CONTEXT="$1"
NAMESPACE="$2"

migrate_postgres_10_to_14 "$KUBE_CONTEXT" "$NAMESPACE"

exit $?

# --- Example Usage ---
# Make sure you are logged into the correct AWS account and have kubectl access.
# ./scripts/postgres-10-to-14-bitnami.sh <kube_context_arn> <namespace_name>
