#!/bin/bash

# upstart.sh - Build, push, and deploy Discord Bot to Kubernetes
# This script builds the Docker image, pushes to GitHub Container Registry,
# and deploys/updates using Helm on your Kubernetes cluster.

set -e  # Exit on any error

# Configuration
REPO_NAME="discordai"
GITHUB_USERNAME="jeffmcneely"
IMAGE_NAME="ghcr.io/${GITHUB_USERNAME}/${REPO_NAME}"
HELM_RELEASE_NAME="discord-bot"
HELM_CHART_PATH="./helm"
NAMESPACE="discord"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if Docker buildx is available
check_buildx() {
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is not available"
        log_error "Please install Docker Desktop or enable buildx"
        log_error "See: https://docs.docker.com/buildx/working-with-buildx/"
        exit 1
    fi
    log_success "Docker buildx is available"
}

# Function to setup buildx builder with enhanced performance
setup_enhanced_builder() {
    log_info "Setting up optimized Docker buildx builder"

    # Create builder with enhanced configuration if it doesn't exist
    if ! docker buildx ls | grep -q "multi-arch"; then
        docker buildx create \
            --name multi-arch \
            --use \
            --driver docker-container \
            --driver-opt network=host \
            --buildkitd-flags '--allow-insecure-entitlement security.insecure --allow-insecure-entitlement network.host'
        log_success "Created optimized multi-arch builder"
    else
        docker buildx use multi-arch
        log_success "Using existing multi-arch builder"
    fi

    # Inspect and start the builder
    docker buildx inspect --bootstrap
}

# Function to inspect the built image
inspect_image() {
    local tag="$1"
    log_info "Inspecting built image: ${IMAGE_NAME}:${tag}"

    docker buildx imagetools inspect "${IMAGE_NAME}:${tag}" || {
        log_warning "Could not inspect image with buildx imagetools"
        log_info "Image built successfully but inspection not available"
    }
}

# Function to test the image locally (optional)
test_image() {
    local tag="$1"
    log_info "Testing the built image locally"

    # Pull the image first
    if docker pull "${IMAGE_NAME}:${tag}" &> /dev/null; then
        # Run a quick test
        if docker run --rm "${IMAGE_NAME}:${tag}" python -c 'import discord; print("✅ Discord import successful")' &> /dev/null; then
            log_success "Image test passed"
        else
            log_warning "Image test failed - this may be expected if running on different architecture"
        fi
    else
        log_warning "Could not pull image for testing"
    fi
}

# Function to get version tag
get_version_tag() {
    # Try to get git commit hash, fallback to timestamp
    if git rev-parse --short HEAD &> /dev/null; then
        echo "$(git rev-parse --short HEAD)"
    else
        echo "$(date +%Y%m%d-%H%M%S)"
    fi
}

# Function to check if we're in the right directory
check_project_directory() {
    if [[ ! -f "Dockerfile" ]] || [[ ! -f "requirements.txt" ]]; then
        log_error "This script must be run from the root of the discordai project directory"
        log_error "Required files/directories not found: Dockerfile, requirements.txt"
        exit 1
    fi
}

# Function to generate content hash for Docker build context
generate_build_hash() {
    log_info "Generating content hash for build context..."
    
    # Generate hash of files that affect the Docker build
    {
        # Core application files
        [[ -f "Dockerfile" ]] && cat Dockerfile
        [[ -f "requirements.txt" ]] && cat requirements.txt
        [[ -f "main.py" ]] && cat main.py
        [[ -f "discord_bot.py" ]] && cat discord_bot.py
        [[ -f "openai_integration.py" ]] && cat openai_integration.py
        [[ -f "message_filter.py" ]] && cat message_filter.py
        [[ -f "test_api.py" ]] && cat test_api.py
        [[ -f "test_copilot.py" ]] && cat test_copilot.py
        [[ -f "test_openai.py" ]] && cat test_openai.py
        
        # Include any Python files in subdirectories (excluding venv and git)
        find . -name "*.py" \
            -not -path "./venv/*" \
            -not -path "./.venv/*" \
            -not -path "./.git/*" \
            -not -path "./__pycache__/*" \
            -not -path "*/__pycache__/*" \
            -exec cat {} \; 2>/dev/null || true
            
    } | sha256sum | cut -d' ' -f1
}

# Function to check if image exists in registry
image_exists_in_registry() {
    local image_name="$1"
    local tag="$2"
    
    log_info "Checking if image exists in registry: ${image_name}:${tag}"
    
    # Try to inspect the image manifest
    if docker buildx imagetools inspect "${image_name}:${tag}" &> /dev/null; then
        return 0  # Image exists
    else
        return 1  # Image doesn't exist
    fi
}

# Function to get build hash from existing image
get_image_build_hash() {
    local image_name="$1"
    local tag="$2"
    
    # Try to get the build hash from the image labels
    local image_hash
    if image_hash=$(docker buildx imagetools inspect "${image_name}:${tag}" --format '{{index .Config.Labels "build.hash"}}' 2>/dev/null); then
        echo "$image_hash"
    else
        echo ""
    fi
}

# Function to check if image is stale using content hash
is_image_stale() {
    local tag="$1"
    local image_name="$2"
    
    log_info "Checking if image build is needed..."
    
    # Check if we should force build
    if [[ "${FORCE_BUILD:-false}" == "true" ]]; then
        log_info "FORCE_BUILD is enabled, skipping staleness check"
        return 0  # Force build
    fi
    
    # Check if image exists in registry
    if ! image_exists_in_registry "$image_name" "$tag"; then
        log_info "Image does not exist in registry, build needed"
        return 0  # Image is stale (needs build)
    fi
    
    # Generate current content hash
    local current_hash=$(generate_build_hash)
    log_info "Current content hash: ${current_hash:0:12}..."
    
    # Get build hash from existing image
    local image_hash=$(get_image_build_hash "$image_name" "$tag")
    
    if [[ -z "$image_hash" ]]; then
        log_warning "Cannot determine image build hash, assuming stale"
        return 0  # Assume stale if we can't determine
    fi
    
    log_info "Image content hash: ${image_hash:0:12}..."
    
    # Compare hashes
    if [[ "$current_hash" != "$image_hash" ]]; then
        log_info "Content changes detected, build needed"
        return 0  # Image is stale
    else
        log_success "Content unchanged, image is up to date"
        return 1  # Image is not stale
    fi
}

# Function to build Docker image
build_image() {
    local tag="$1"
    local build_mode="${BUILD_MODE:-multi-arch}"
    
    # Check if build is needed (unless skipping check)
    if [[ "${SKIP_BUILD_CHECK:-false}" != "true" ]]; then
        if ! is_image_stale "$tag" "$IMAGE_NAME"; then
            log_success "Image is up to date, skipping build"
            return 0
        fi
    else
        log_info "Skipping staleness check, proceeding with build"
    fi
    
    log_info "Building new Docker image..."
    
    if [[ "${build_mode}" == "local" ]]; then
        build_local_image "${tag}"
    else
        build_multiarch_image "${tag}"
    fi
}

# Function to build local single-architecture image (faster for development)
build_local_image() {
    local tag="$1"
    local build_hash=$(generate_build_hash)
    local build_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    log_info "Building local Docker image: ${IMAGE_NAME}:${tag}"
    log_info "Build hash: ${build_hash:0:12}..."

    if ! docker build \
        --tag "${IMAGE_NAME}:${tag}" \
        --tag "${IMAGE_NAME}:latest" \
        --label "build.hash=${build_hash}" \
        --label "build.timestamp=${build_timestamp}" \
        --label "build.git-commit=${git_commit}" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --cache-from "${IMAGE_NAME}:latest" \
        .; then
        log_error "Failed to build local Docker image"
        exit 1
    fi

    log_success "Local Docker image built successfully"
    
    # Push the image
    if [[ "${PUSH_IMAGE:-true}" == "true" ]]; then
        docker push "${IMAGE_NAME}:${tag}"
        docker push "${IMAGE_NAME}:latest"
        log_success "Local image pushed successfully"
    fi
}

# Function to build multi-architecture image
build_multiarch_image() {
    local tag="$1"
    local build_hash=$(generate_build_hash)
    local build_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    log_info "Building Docker image for multiple architectures: ${IMAGE_NAME}:${tag}"
    log_info "Build hash: ${build_hash:0:12}..."

    # Check buildx availability
    check_buildx

    # Setup buildx builder with enhanced performance
    setup_enhanced_builder

    # Build and push multi-architecture image with optimizations and metadata
    log_info "Building for platforms: linux/amd64,linux/arm64"

    if ! docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --tag "${IMAGE_NAME}:${tag}" \
        --tag "${IMAGE_NAME}:latest" \
        --label "build.hash=${build_hash}" \
        --label "build.timestamp=${build_timestamp}" \
        --label "build.git-commit=${git_commit}" \
        --cache-from type=gha \
        --cache-to type=gha,mode=max \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --push \
        .; then
        log_error "Failed to build multi-architecture Docker image"
        exit 1
    fi

    log_success "Multi-architecture Docker image built and pushed successfully"

    # Inspect the built image
    inspect_image "${tag}"

    # Optionally test the image
    if [[ "${TEST_IMAGE:-false}" == "true" ]]; then
        test_image "${tag}"
    fi
}

# Function to check Kubernetes connection
check_kubernetes() {
    log_info "Checking Kubernetes connection"

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Please ensure kubectl is configured and you have access to your cluster"
        exit 1
    fi

    log_success "Connected to Kubernetes cluster: $(kubectl config current-context)"
}

# Function to handle Redis PVC cleanup and recreation
handle_redis_storage_upgrade() {
    local release_name="$1"
    local namespace="$2"
    
    log_info "Checking Redis storage configuration..."
    
    # Check if Redis PVCs exist without storageClass
    local redis_pvcs=($(kubectl get pvc -n "${namespace}" -l app.kubernetes.io/name=redis --no-headers 2>/dev/null | awk '{print $1}' | grep -E "(redis-master|redis-replica)" || true))
    
    if [[ ${#redis_pvcs[@]} -gt 0 ]]; then
        for pvc in "${redis_pvcs[@]}"; do
            # Check if PVC has no storageClass
            local storage_class=$(kubectl get pvc "${pvc}" -n "${namespace}" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
            if [[ -z "$storage_class" ]]; then
                log_warning "PVC ${pvc} has no storageClass, needs recreation"
                
                # Delete the StatefulSet first to release the PVC
                local sts_name="${pvc%-data*}"  # Remove -data suffix to get StatefulSet name
                if kubectl get statefulset "${sts_name}" -n "${namespace}" &> /dev/null; then
                    log_info "Scaling down StatefulSet ${sts_name}..."
                    kubectl scale statefulset "${sts_name}" --replicas=0 -n "${namespace}"
                    kubectl wait --for=delete pod -l "statefulset.kubernetes.io/pod-name" \
                        -n "${namespace}" --timeout=120s || true
                    
                    log_info "Deleting StatefulSet ${sts_name}..."
                    kubectl delete statefulset "${sts_name}" -n "${namespace}" --ignore-not-found=true
                fi
                
                # Delete the PVC
                log_info "Deleting PVC ${pvc} for recreation with local-path storage..."
                kubectl delete pvc "${pvc}" -n "${namespace}" --ignore-not-found=true
                
                log_success "PVC ${pvc} prepared for recreation with proper storage class"
            else
                log_success "PVC ${pvc} already has storageClass: ${storage_class}"
            fi
        done
    else
        log_info "No Redis PVCs found or all have proper storage class"
    fi
}

# Function to handle StatefulSet recreation if needed
handle_statefulset_upgrade() {
    local release_name="$1"
    local namespace="$2"
    
    log_info "Checking for StatefulSet upgrade issues..."
    
    # List of StatefulSets that might need recreation
    local statefulsets=(
        "${release_name}-redis-master"
    )
    
    for sts in "${statefulsets[@]}"; do
        if kubectl get statefulset "${sts}" --namespace "${namespace}" &> /dev/null; then
            log_info "Found StatefulSet: ${sts}"
            
            # Scale down to 0 first to ensure clean shutdown
            log_info "Scaling down StatefulSet ${sts} to 0 replicas..."
            kubectl scale statefulset "${sts}" --replicas=0 --namespace "${namespace}"
            
            # Wait for pods to terminate
            kubectl wait --for=delete pod -l "app.kubernetes.io/component=master,app.kubernetes.io/name=redis" \
                --namespace "${namespace}" --timeout=120s || true
            
            # Delete the StatefulSet (keeping PVCs for data persistence)
            log_info "Deleting StatefulSet ${sts} (preserving data)..."
            kubectl delete statefulset "${sts}" --namespace "${namespace}" --ignore-not-found=true
            
            # Wait for StatefulSet to be fully deleted
            kubectl wait --for=delete statefulset/"${sts}" --namespace "${namespace}" --timeout=120s || true
            
            log_success "StatefulSet ${sts} prepared for recreation"
        fi
    done
}

# Function to deploy/update with Helm
deploy_helm() {
    local tag="$1"
    log_info "Deploying/updating Helm release: ${HELM_RELEASE_NAME}"

    # Check if custom-values.yaml exists
    if [[ ! -f "custom-values.yaml" ]]; then
        log_error "custom-values.yaml not found!"
        log_error "Please create custom-values.yaml with your environment configuration."
        log_error "You can copy values.yaml as a starting template:"
        log_error "  cp helm/values.yaml custom-values.yaml"
        log_error "Then edit custom-values.yaml with your secrets and configuration."
        exit 1
    fi

    # Update Helm dependencies to ensure we have the latest charts
    log_info "Updating Helm dependencies..."
    if ! helm dependency update "${HELM_CHART_PATH}"; then
        log_error "Failed to update Helm dependencies"
        exit 1
    fi
    log_success "Helm dependencies updated"

    # Check if Helm release exists
    if helm list -q --namespace "${NAMESPACE}" | grep -q "^${HELM_RELEASE_NAME}$"; then
        log_info "Upgrading existing Helm release"
        
        # Handle Redis storage upgrade if needed
        handle_redis_storage_upgrade "${HELM_RELEASE_NAME}" "${NAMESPACE}"
        
        # Try the upgrade first
        if ! helm upgrade "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
            --namespace "${NAMESPACE}" \
            --values custom-values.yaml \
            --set image.tag="${tag}" \
            --wait \
            --timeout 600s 2>/dev/null; then
            
            log_warning "Initial upgrade failed, likely due to StatefulSet immutable fields"
            log_info "Handling StatefulSet recreation..."
            
            # Handle StatefulSet recreation
            handle_statefulset_upgrade "${HELM_RELEASE_NAME}" "${NAMESPACE}"
            
            # Retry the upgrade after StatefulSet cleanup
            log_info "Retrying Helm upgrade after StatefulSet cleanup..."
            helm upgrade "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
                --namespace "${NAMESPACE}" \
                --values custom-values.yaml \
                --set image.tag="${tag}" \
                --wait \
                --timeout 600s
        fi
    else
        log_info "Installing new Helm release"
        helm install "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
            --namespace "${NAMESPACE}" \
            --values custom-values.yaml \
            --set image.tag="${tag}" \
            --create-namespace \
            --wait \
            --timeout 600s
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Helm deployment completed successfully"
    else
        log_error "Helm deployment failed"
        exit 1
    fi
}

# Function to show deployment status
show_status() {
    log_info "Checking deployment status"

    echo ""
    echo "=== Deployment Status ==="
    kubectl get pods --namespace "${NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE_NAME}"
    echo ""
    kubectl get svc --namespace "${NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE_NAME}"
    echo ""
    kubectl get ingress --namespace "${NAMESPACE}" -l "app.kubernetes.io/name=${HELM_RELEASE_NAME}"
}

# Function to load environment variables from .env file
load_env_file() {
    if [[ -f ".env" ]]; then
        log_info "Loading environment variables from .env file"
        set -a  # automatically export all variables
        source .env
        set +a
        log_success "Environment variables loaded from .env file"
    else
        log_info ".env file not found, using existing environment variables"
    fi
}

# Function to cleanup Docker images (placeholder for future implementation)
cleanup_images() {
    log_info "Cleaning up old Docker images"
    # This function can be implemented later to clean up old images
}

# Function to cleanup buildx resources
cleanup_buildx() {
    log_info "Cleaning up buildx resources"

    # Remove builder if it was created by this script and we're not keeping it
    if [[ "${KEEP_BUILDER:-false}" != "true" ]] && docker buildx ls | grep -q "multi-arch"; then
        docker buildx rm multi-arch 2>/dev/null || true
        log_success "Buildx builder cleaned up"
    fi
}

# Trap to ensure cleanup on exit
trap 'cleanup_buildx' EXIT

# Main function
main() {
    echo "🚀 Discord Bot Upstart Script"
    echo "=============================="
    echo ""

    # Pre-flight checks
    log_info "Running pre-flight checks..."

    check_command "docker"
    check_command "kubectl"
    check_command "helm"
    check_command "git"

    check_project_directory

    # Check Docker daemon
    if ! docker system info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    # Get version tag
    VERSION_TAG=$(get_version_tag)
    log_info "Using version tag: ${VERSION_TAG}"

    # Build Docker image
    build_image "${VERSION_TAG}"

    # Check Kubernetes connection
    check_kubernetes

    # Deploy with Helm
    deploy_helm "${VERSION_TAG}"

    # Show status
    show_status

    # Cleanup
    cleanup_images
    cleanup_buildx

    echo ""
    log_success "🎉 Deployment completed successfully!"
    log_success "Your Discord bot has been updated to version: ${VERSION_TAG}"
    echo ""
    log_info "To check logs: kubectl logs -f deployment/${HELM_RELEASE_NAME} --namespace ${NAMESPACE}"
    log_info "To restart: kubectl rollout restart deployment/${HELM_RELEASE_NAME} --namespace ${NAMESPACE}"
}

# Function to show help
show_help() {
    echo "Discord Bot Upstart Script"
    echo ""
    echo "This script builds the Docker image, pushes to GitHub Container Registry,"
    echo "and deploys/updates using Helm on your Kubernetes cluster."
    echo ""
    echo "Usage:"
    echo "  ./upstart.sh              # Run the full deployment process"
    echo "  ./upstart.sh --help       # Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  GITHUB_TOKEN              # GitHub Personal Access Token (for ghcr.io)"
    echo "  KUBECONFIG               # Path to kubeconfig file"
    echo "  TEST_IMAGE               # Set to 'true' to test image after build (default: false)"
    echo "  KEEP_BUILDER             # Set to 'true' to keep buildx builder after deployment (default: false)"
    echo "  BUILD_MODE               # Set to 'local' for faster single-arch builds (default: multi-arch)"
    echo "  PUSH_IMAGE               # Set to 'false' to skip pushing in local mode (default: true)"
    echo "  FORCE_BUILD              # Set to 'true' to force rebuild even if image is up to date (default: false)"
    echo "  SKIP_BUILD_CHECK         # Set to 'true' to skip staleness check and always build (default: false)"
    echo ""
    echo "Build Optimization:"
    echo "  The script uses content hash-based detection to avoid unnecessary rebuilds."
    echo "  Images are only rebuilt when source code or dependencies have changed."
    echo ""
    echo "Configuration:"
    echo "  Uses custom-values.yaml for deployment configuration (environment variables)."
    echo "  Run './deploy-config.sh' first to create/update custom-values.yaml with your secrets."
    echo "  No Kubernetes secrets are used - all configuration via environment variables."
    echo ""
    echo "Requirements:"
    echo "  - Docker with buildx support (Docker Desktop recommended)"
    echo "  - kubectl configured for your cluster"
    echo "  - helm installed"
    echo "  - Git repository initialized"
    echo "  - Access to push to ghcr.io/${GITHUB_USERNAME}/${REPO_NAME}"
    echo ""
    echo "The script will:"
    echo "  1. Check all prerequisites and Docker buildx setup"
    echo "  2. Verify custom-values.yaml exists with your configuration"
    echo "  3. Build the Docker image for AMD64 and ARM64 architectures (if needed)"
    echo "  4. Push the multi-architecture image to GitHub Container Registry"
    echo "  5. Deploy/update the Helm release on Kubernetes using custom-values.yaml"
    echo "  6. Show deployment status"
    echo "  7. Clean up build resources"
    echo ""
    echo "Platforms supported: linux/amd64, linux/arm64"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac