# platform-gitops Makefile - Standardized Development Operations

.PHONY: all validate test deploy clean

# Default target
all: validate

# Validate YAML syntax and kustomize
validate:
	@echo "Validating manifests..."
	kubeconform -strict -summary clusters/cryptophys-work/base
	kustomize build clusters/cryptophys-work/base --enable-alpha-plugins
	@echo "✅ Validation passed"

# Run kyverno policies test
test:
	@echo "Running policy tests..."
	kubectl kyverno apply -f clusters/cryptophys-work/overlays/production --dry-run
	@echo "✅ Tests passed"

# Deploy to cluster (requires kubectl context)
deploy:
	@echo "Deploying to cryptophys-work..."
	kustomize build clusters/cryptophys-work/overlays/production | kubectl apply -f -
	@echo "✅ Deployed"

# Clean up generated files
clean:
	rm -rf _generated/

# Show cluster status
status:
	kubectl get nodes -o wide
	kubectl get pods -A | head -20

# Sync flux from git
sync:
	flux reconcile source git flux-system -n flux-system

# Verify reconciliation
verify:
	flux get all -A
