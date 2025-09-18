#!/bin/bash

# build-multiarch.sh - Test multi-architecture Docker builds locally
# This script helps test the multi-architecture build process

set -e

# Configuration
IMAGE_NAME="discord-bot-test"
PLATFORMS="linux/amd64,linux/arm64"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Function to check if Docker buildx is available
check_buildx() {
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is not available"
        log_error "Please install Docker Desktop or enable buildx"
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

# Function to build multi-architecture image
build_multiarch() {
    log_info "Building multi-architecture image: ${IMAGE_NAME}"
    log_info "Platforms: ${PLATFORMS}"

    # Build the image
    docker buildx build \
        --platform "${PLATFORMS}" \
        --tag "${IMAGE_NAME}:latest" \
        --load \
        .

    if [[ $? -eq 0 ]]; then
        log_success "Multi-architecture build completed successfully"
    else
        log_error "Multi-architecture build failed"
        exit 1
    fi
}

# Function to inspect the built image
inspect_image() {
    log_info "Inspecting built image"

    docker buildx imagetools inspect "${IMAGE_NAME}:latest" || {
        log_warning "Could not inspect image with buildx imagetools"
        log_info "Trying with regular docker inspect"
        docker inspect "${IMAGE_NAME}:latest"
    }
}

# Function to test the image
test_image() {
    log_info "Testing the built image"

    # Run a quick test
    docker run --rm "${IMAGE_NAME}:latest" python -c "import discord; print('✅ Discord import successful')" || {
        log_error "Image test failed"
        exit 1
    }

    log_success "Image test passed"
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up test resources"

    # Remove the test image
    docker rmi "${IMAGE_NAME}:latest" 2>/dev/null || true

    # Remove builder if it was created by this script
    if docker buildx ls | grep -q "multi-arch"; then
        docker buildx rm multi-arch 2>/dev/null || true
    fi

    log_success "Cleanup completed"
}

# Function to show help
show_help() {
    echo "Multi-Architecture Docker Build Test Script"
    echo ""
    echo "This script tests building Docker images for multiple architectures."
    echo ""
    echo "Usage:"
    echo "  ./build-multiarch.sh          # Run full test (build, inspect, test, cleanup)"
    echo "  ./build-multiarch.sh --build  # Only build the image"
    echo "  ./build-multiarch.sh --test   # Only test existing image"
    echo "  ./build-multiarch.sh --help   # Show this help"
    echo ""
    echo "Requirements:"
    echo "  - Docker with buildx support"
    echo "  - Docker Desktop (recommended) or buildx installed"
    echo ""
    echo "Platforms: ${PLATFORMS}"
    echo "Image: ${IMAGE_NAME}"
}

# Main function
main() {
    local action="full"

    # Parse command line arguments
    case "${1:-}" in
        --build)
            action="build"
            ;;
        --test)
            action="test"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            action="full"
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    echo "🏗️  Multi-Architecture Docker Build Test"
    echo "========================================"

    case "${action}" in
        "build")
            check_buildx
            setup_builder
            build_multiarch
            inspect_image
            ;;
        "test")
            test_image
            ;;
        "full")
            check_buildx
            setup_builder
            build_multiarch
            inspect_image
            test_image
            cleanup
            ;;
    esac

    echo ""
    log_success "🎉 Multi-architecture build test completed!"
}

# Run main function
main "$@"