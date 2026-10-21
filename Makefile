SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
INVENTORY ?= inventory/lab/hosts.yml
ANSIBLE_PLAYBOOK ?= ansible-playbook -i $(INVENTORY)

.PHONY: help lint syntax-check preflight bootstrap base services platform observability deploy health backup tunnels clean

help: ## Muestra este menu de ayuda con los objetivos documentados
	@echo "=================================================================="
	@echo "   AUTOMATIZACION DEVOPS/SRE - CLUSTER BARE-METAL K8S & OPENSTACK"
	@echo "=================================================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

lint: ## Ejecuta validaciones estaticas de codigo (ansible-lint, yamllint, shellcheck)
	@echo "==> [1/3] Ejecutando yamllint..."
	@PATH="$$HOME/.local/bin:$$PATH" yamllint -c .yamllint .
	@echo "==> [2/3] Ejecutando ansible-lint..."
	@PATH="$$HOME/.local/bin:$$PATH" ansible-lint ansible/site.yml
	@echo "==> [3/3] Ejecutando shellcheck..."
	@PATH="$$HOME/.local/bin:$$PATH" find scripts/ network/ -name "*.sh" -exec shellcheck -e SC1090,SC1091,SC2034,SC2086,SC2012 {} +
	@echo "==> Validaciones estaticas completadas exitosamente."

syntax-check: ## Valida la sintaxis de todos los playbooks de Ansible
	@echo "==> Validando sintaxis de playbooks de Ansible..."
	@$(ANSIBLE_PLAYBOOK) ansible/site.yml --syntax-check

preflight: ## [Fase 00] Ejecuta pruebas previas de conectividad y auditoria de hardware
	@echo "==> Ejecutando Fase 00: Preflight..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/00-preflight/00_ping.yml
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/00-preflight/02_system_summary.yml

bootstrap: ## Inyecta y distribuye llaves SSH en la flota de servidores
	@echo "==> Ejecutando distribucion de llaves SSH..."
	@./scripts/bootstrap/setup_keys.sh

base: ## [Fase 10] Aplica configuracion base del SO y endurecimiento del Bastion
	@echo "==> Ejecutando Fase 10: Base y Hardening de Bastion..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/10-base/01_os_base.yml
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/10-base/02_bastion_hardening.yml

services: ## [Fase 20] Despliega Nexus 3, PXE Controller y OpenStack Ironic Standalone
	@echo "==> Ejecutando Fase 20: Servicios Centrales..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/20-services/01_nexus.yml
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/20-services/02_pxe_controller.yml
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/20-services/03_ironic_deploy.yml

platform: ## [Fase 30] Despliega el cluster Kubernetes HA (RKE2 + Cilium eBPF)
	@echo "==> Ejecutando Fase 30: Plataforma Kubernetes HA..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/30-platform/01_rke2_cluster.yml

observability: ## [Fase 40] Despliega la suite de observabilidad (Prometheus, Grafana, Node Exporter)
	@echo "==> Ejecutando Fase 40: Suite de Observabilidad..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/40-observability/01_monitoring.yml

deploy: preflight base services platform observability ## Despliega toda la infraestructura end-to-end

health: ## [Fase 50] Ejecuta diagnostico integral de salud de la flota en terminal
	@echo "==> Ejecutando verificacion de salud operativa..."
	@./scripts/diagnostics/healthcheck.sh

backup: ## [Fase 90] Genera respaldos y snapshots de contingencia (DR)
	@echo "==> Ejecutando respaldo de desastres..."
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup

tunnels: ## Abre tuneles SSH locales para dashboards (Grafana, Horizon, Nexus)
	@echo "==> Abriendo tuneles SSH seguros..."
	@./scripts/client/tunnels.sh

clean: ## Limpia archivos temporales, logs y caches locales
	@echo "==> Limpiando archivos temporales..."
	@find . -type f -name "*.retry" -delete
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
