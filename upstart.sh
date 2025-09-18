#!/bin/bash

# upstart.sh - Build, push, and deploy Discord Bot to Kubernetes
# This script builds the Docker image, pushes to GitHub Container Registry,
# and deploys/updates using Helm on your Kubernetes cluster.

set -e  # Exit on any error

# Trap to ensure cleanup on exit
trap 'cleanup_buildx' EXIT

# Configuration
REPO_NAME="discordai"
GITHUB_USERNAME="jeffmcneely"
IMAGE_NAME="ghcr.io/${GITHUB_USERNAME}/${REPO_NAME}"
HELM_RELEASE_NAME="discord-bot"
HELM_CHART_PATH="./helm/discord-bot"
NAMESPACE="bggdl"

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

# Function to setup buildx builder
setup_builder() {
    log_info "Setting up Docker buildx builder"

    # Create builder if it doesn't exist
    if ! docker buildx ls | grep -q "multi-arch"; then
        docker buildx create --name multi-arch --use
        log_success "Created multi-arch builder"
    else
        docker buildx use multi-arch
        log_success "Using existing multi-arch builder"
    fi
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
        if docker run --rm "${IMAGE_NAME}:${tag}" python -c "import discord; print('✅ Discord import successful')" &> /dev/null; then
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
    if [[ ! -f "Dockerfile" ]] || [[ ! -f "requirements.txt" ]] || [[ ! -d "helm/discord-bot" ]]; then
        log_error "This script must be run from the root of the discordai project directory"
        log_error "Required files/directories not found: Dockerfile, requirements.txt, helm/discord-bot/"
        exit 1
    fi
}

# Function to build Docker image
build_image() {
    local tag="$1"
    log_info "Building Docker image for multiple architectures: ${IMAGE_NAME}:${tag}"

    # Check buildx availability
    check_buildx

    # Setup buildx builder
    setup_builder

    # Build and push multi-architecture image
    log_info "Building for platforms: linux/amd64,linux/arm64"

    if ! docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --tag "${IMAGE_NAME}:${tag}" \
        --tag "${IMAGE_NAME}:latest" \
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

# Function to deploy/update with Helm
deploy_helm() {
    local tag="$1"
    log_info "Deploying/updating Helm release: ${HELM_RELEASE_NAME}"

    # Check if Helm release exists
    if helm list -q --namespace "${NAMESPACE}" | grep -q "^${HELM_RELEASE_NAME}$"; then
        log_info "Upgrading existing Helm release"
        helm upgrade "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
            --namespace "${NAMESPACE}" \
            --set image.tag="${tag}" \
            --wait \
            --timeout 600s
    else
        log_info "Installing new Helm release"
        helm install "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
            --namespace "${NAMESPACE}" \
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

# Function to cleanup buildx resources
cleanup_buildx() {
    log_info "Cleaning up buildx resources"

    # Remove builder if it was created by this script and we're not keeping it
    if [[ "${KEEP_BUILDER:-false}" != "true" ]] && docker buildx ls | grep -q "multi-arch"; then
        docker buildx rm multi-arch 2>/dev/null || true
        log_success "Buildx builder cleaned up"
    fi
}

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
    echo "  DISCORD_DB_URL            # PostgreSQL connection string (optional)"
    echo "  TEST_IMAGE               # Set to 'true' to test image after build (default: false)"
    echo "  KEEP_BUILDER             # Set to 'true' to keep buildx builder after deployment (default: false)"
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
    echo "  2. Build the Docker image for AMD64 and ARM64 architectures"
    echo "  3. Push the multi-architecture image to GitHub Container Registry"
    echo "  4. Deploy/update the Helm release on Kubernetes"
    echo "  5. Show deployment status"
    echo "  6. Clean up old Docker images and build cache"
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