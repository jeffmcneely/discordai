#!/bin/bash

# deploy-config.sh - Helper script to configure secrets for Discord Bot deployment
# This script helps you set up the necessary Kubernetes secrets for your Discord bot

set -e

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

# Function to create Kubernetes secret
create_secret() {
    local secret_name="discordai"
    local namespace="${1:-default}"

    log_info "Creating Kubernetes secret: ${secret_name} in namespace: ${namespace}"

    # Check if secret already exists
    if kubectl get secret "${secret_name}" --namespace "${namespace}" &> /dev/null; then
        log_warning "Secret ${secret_name} already exists. Updating..."
        kubectl delete secret "${secret_name}" --namespace "${namespace}"
    fi

    # Create the secret
    kubectl create secret generic "${secret_name}" \
        --namespace "${namespace}" \
        --from-literal=DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN}" \
        --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY}" \
        --from-literal=OPENAI_MODEL="${OPENAI_MODEL:-gpt-3.5-turbo}" \
        --from-literal=OPENAI_MAX_TOKENS="${OPENAI_MAX_TOKENS:-1000}" \
        --from-literal=OPENAI_TEMPERATURE="${OPENAI_TEMPERATURE:-0.7}" \
        --from-literal=OPENAI_INTEGRATION_ENABLED="${OPENAI_INTEGRATION_ENABLED:-true}" \
        --from-literal=RATE_LIMIT_MESSAGES_PER_MINUTE="${RATE_LIMIT_MESSAGES_PER_MINUTE:-5}" \
        --from-literal=RATE_LIMIT_TOKENS_PER_HOUR="${RATE_LIMIT_TOKENS_PER_HOUR:-10000}" \

    log_success "Secret created successfully"
}

# Function to validate environment variables
validate_env() {
    local missing_vars=()

    if [[ -z "${DISCORD_BOT_TOKEN}" ]]; then
        missing_vars+=("DISCORD_BOT_TOKEN")
    fi

    if [[ -z "${OPENAI_API_KEY}" ]]; then
        missing_vars+=("OPENAI_API_KEY")
    fi

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        log_info "Please set these variables and run the script again:"
        echo "  export DISCORD_BOT_TOKEN='your_discord_token'"
        echo "  export OPENAI_API_KEY='your_openai_key'"
        echo "  ./deploy-config.sh"
        exit 1
    fi
}

# Function to show current configuration
show_config() {
    echo ""
    echo "=== Current Configuration ==="
    echo "Discord Bot Token: ${DISCORD_BOT_TOKEN:+****$(echo $DISCORD_BOT_TOKEN | tail -c 10)}"
    echo "OpenAI API Key: ${OPENAI_API_KEY:+****$(echo $OPENAI_API_KEY | tail -c 10)}"
    echo "OpenAI Model: ${OPENAI_MODEL:-gpt-3.5-turbo}"
    echo "Max Tokens: ${OPENAI_MAX_TOKENS:-1000}"
    echo "Temperature: ${OPENAI_TEMPERATURE:-0.7}"
    echo "Integration Enabled: ${OPENAI_INTEGRATION_ENABLED:-true}"
    echo "Rate Limit (messages/min): ${RATE_LIMIT_MESSAGES_PER_MINUTE:-5}"
    echo "Rate Limit (tokens/hour): ${RATE_LIMIT_TOKENS_PER_HOUR:-10000}"
    echo ""
}

# Function to show help
show_help() {
    echo "Discord Bot Deployment Configuration Helper"
    echo ""
    echo "This script helps you create the necessary Kubernetes secrets for your Discord bot."
    echo ""
    echo "Usage:"
    echo "  ./deploy-config.sh                    # Create secret with current environment variables"
    echo "  ./deploy-config.sh --namespace prod   # Create secret in specific namespace"
    echo "  ./deploy-config.sh --help            # Show this help"
    echo ""
    echo "Required Environment Variables:"
    echo "  DISCORD_BOT_TOKEN     Your Discord bot token"
    echo "  OPENAI_API_KEY        Your OpenAI API key"
    echo ""
    echo "Optional Environment Variables:"
    echo "  OPENAI_MODEL                     Default: gpt-3.5-turbo"
    echo "  OPENAI_MAX_TOKENS               Default: 1000"
    echo "  OPENAI_TEMPERATURE              Default: 0.7"
    echo "  OPENAI_INTEGRATION_ENABLED      Default: true"
    echo "  RATE_LIMIT_MESSAGES_PER_MINUTE  Default: 5"
    echo "  RATE_LIMIT_TOKENS_PER_HOUR      Default: 10000"
    echo ""
    echo "Example:"
    echo "  export DISCORD_BOT_TOKEN='your_token_here'"
    echo "  export OPENAI_API_KEY='your_key_here'"
    echo "  ./deploy-config.sh"
}

# Main function
main() {
    local namespace="default"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                namespace="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "🔧 Discord Bot Deployment Configuration"
    echo "========================================"

    # Validate environment
    validate_env

    # Show current configuration
    show_config

    # Confirm with user
    read -p "Do you want to create the Kubernetes secret with these settings? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi

    # Create the secret
    create_secret "${namespace}"

    echo ""
    log_success "Configuration complete!"
    log_info "You can now run './upstart.sh' to build and deploy your bot"
    log_info "Or manually deploy with: helm install discord-bot ./helm/discord-bot --namespace ${namespace}"
}

# Run main function
main "$@"