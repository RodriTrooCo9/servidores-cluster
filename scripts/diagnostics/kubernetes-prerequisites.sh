#!/usr/bin/env bash
# Solo lectura: usa el contexto actual de kubectl o KUBECONFIG.
set -Eeuo pipefail

command -v kubectl >/dev/null
command -v python3 >/dev/null
for crd in opentelemetrycollectors.opentelemetry.io instrumentations.opentelemetry.io; do
    kubectl wait --for=condition=Established --timeout=15s "crd/${crd}"
done
kubectl get storageclass local-path -o name
kubectl get deployments --all-namespaces -o json | python3 -c '
import json, sys
items = json.load(sys.stdin)["items"]
operators = [d for d in items if any(
    "opentelemetry-operator" in c.get("image", "")
    for c in d["spec"]["template"]["spec"].get("containers", []))]
if not operators or not any(d.get("status", {}).get("availableReplicas", 0) > 0 for d in operators):
    sys.exit("ERROR: No hay un Deployment disponible del operador OpenTelemetry")
print("Operador OpenTelemetry disponible")
'
echo "Prerrequisitos básicos presentes. Pendiente verificar webhooks, aprovisionamiento PVC e ingesta real."
