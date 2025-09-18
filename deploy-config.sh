#!/bin/bash

# deploy-config.sh - Helper script to configure custom-values.yaml for Discord Bot deployment
# This script helps you set up the necessary configuration file for your Discord bot

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

# Function to create/update custom-values.yaml file
create_custom_values() {
    local namespace="${1:-discord}"
    local values_file="custom-values.yaml"

    log_info "Creating/updating custom values file: ${values_file}"

    # Check if custom-values.yaml exists
    if [[ -f "${values_file}" ]]; then
        log_warning "Custom values file already exists. Creating backup..."
        cp "${values_file}" "${values_file}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Backup created: ${values_file}.backup.$(date +%Y%m%d-%H%M%S)"
    else
        # Copy template from helm values
        if [[ -f "helm/discord-bot/values.yaml" ]]; then
            log_info "Creating custom-values.yaml from template..."
            cp "helm/discord-bot/values.yaml" "${values_file}"
        else
            log_error "Template values.yaml not found at helm/discord-bot/values.yaml"
            exit 1
        fi
    fi

    # Update the values file with environment variables
    log_info "Updating configuration values..."

    # Create a temporary file with the updated values
    cat > "${values_file}" << EOF
# Custom values for discord-bot deployment
# This file contains environment-specific configuration and secrets
# DO NOT COMMIT this file to Git - it contains sensitive information

replicaCount: 1

image:
  repository: ghcr.io/jeffmcneely/discordai
  pullPolicy: Always
  tag: latest

imagePullSecrets:
  - name: ghcr-secret

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 2000

securityContext:
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: discord-bot.local
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80

nodeSelector: {}

tolerations: []

affinity: {}

# Discord Bot Configuration
discordBot:
  logLevel: INFO
  maxMessagesPerMinute: 10

# Redis Configuration
redis:
  enabled: true
  auth:
    enabled: false
  master:
    persistence:
      enabled: true
      size: 1Gi

# PostgreSQL Configuration (Remote Database)
postgresql:
  enabled: false

# Monitoring and Observability
monitoring:
  enabled: false
  prometheus:
    enabled: false
  grafana:
    enabled: false

# Environment Variables - These will be injected into the pod
env:
  DISCORD_BOT_TOKEN: "${DISCORD_BOT_TOKEN}"
  OPENAI_API_KEY: "${OPENAI_API_KEY}"
  OPENAI_MODEL: "${OPENAI_MODEL:-gpt-5-nano}"
  OPENAI_MAX_TOKENS: "${OPENAI_MAX_TOKENS:-1000}"
  OPENAI_TEMPERATURE: "${OPENAI_TEMPERATURE:-0.7}"
  OPENAI_INTEGRATION_ENABLED: "${OPENAI_INTEGRATION_ENABLED:-true}"
  RATE_LIMIT_MESSAGES_PER_MINUTE: "${RATE_LIMIT_MESSAGES_PER_MINUTE:-5}"
  RATE_LIMIT_TOKENS_PER_HOUR: "${RATE_LIMIT_TOKENS_PER_HOUR:-10000}"
  DISCORD_DB_URL: "${DISCORD_DB_URL:-}"
EOF

    log_success "Custom values file created/updated successfully"
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
    local namespace="${1:-discord}"
    echo ""
    echo "=== Current Configuration ==="
    echo "Namespace: ${namespace}"
    echo "Discord Bot Token: ${DISCORD_BOT_TOKEN:+****$(echo $DISCORD_BOT_TOKEN | tail -c 10)}"
    echo "OpenAI API Key: ${OPENAI_API_KEY:+****$(echo $OPENAI_API_KEY | tail -c 10)}"
    echo "OpenAI Model: ${OPENAI_MODEL:-gpt-5-nano}"
    echo "Max Tokens: ${OPENAI_MAX_TOKENS:-1000}"
    echo "Temperature: ${OPENAI_TEMPERATURE:-0.7}"
    echo "Integration Enabled: ${OPENAI_INTEGRATION_ENABLED:-true}"
    echo "Rate Limit (messages/min): ${RATE_LIMIT_MESSAGES_PER_MINUTE:-5}"
    echo "Rate Limit (tokens/hour): ${RATE_LIMIT_TOKENS_PER_HOUR:-10000}"
    echo "Database URL: ${DISCORD_DB_URL:+****configured}"
    echo ""
    echo "Output file: custom-values.yaml"
    echo ""
}

# Function to show help
show_help() {
    echo "Discord Bot Configuration Helper"
    echo ""
    echo "This script helps you create the custom-values.yaml file for your Discord bot deployment."
    echo "It uses environment variables to configure the application (no Kubernetes secrets)."
    echo ""
    echo "Usage:"
    echo "  ./deploy-config.sh                    # Create custom-values.yaml with current environment variables"
    echo "  ./deploy-config.sh --namespace prod   # Specify target namespace (informational only)"
    echo "  ./deploy-config.sh --help            # Show this help"
    echo ""
    echo "Required Environment Variables:"
    echo "  DISCORD_BOT_TOKEN     Your Discord bot token"
    echo "  OPENAI_API_KEY        Your OpenAI API key"
    echo ""
    echo "Optional Environment Variables:"
    echo "  OPENAI_MODEL                     Default: gpt-5-nano"
    echo "  OPENAI_MAX_TOKENS               Default: 1000"
    echo "  OPENAI_TEMPERATURE              Default: 0.7"
    echo "  OPENAI_INTEGRATION_ENABLED      Default: true"
    echo "  RATE_LIMIT_MESSAGES_PER_MINUTE  Default: 5"
    echo "  RATE_LIMIT_TOKENS_PER_HOUR      Default: 10000"
    echo "  DISCORD_DB_URL                  PostgreSQL connection string (optional)"
    echo ""
    echo "Example:"
    echo "  export DISCORD_BOT_TOKEN='your_token_here'"
    echo "  export OPENAI_API_KEY='your_key_here'"
    echo "  ./deploy-config.sh"
    echo ""
    echo "Output:"
    echo "  Creates/updates custom-values.yaml with your configuration"
    echo "  This file is used by upstart.sh for deployment"
    echo "  The file is automatically added to .gitignore"
}

# Main function
main() {
    local namespace="discord"

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

    echo "🔧 Discord Bot Configuration Helper"
    echo "===================================="

    # Validate environment
    validate_env

    # Show current configuration
    show_config "${namespace}"

    # Confirm with user
    read -p "Do you want to create/update custom-values.yaml with these settings? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi

    # Create the custom values file
    create_custom_values "${namespace}"

    echo ""
    log_success "Configuration complete!"
    log_info "Created: custom-values.yaml"
    log_info "You can now run './upstart.sh' to deploy your bot"
    log_warning "Remember: custom-values.yaml contains secrets and is excluded from Git"
}

# Run main function
main "$@"