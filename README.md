# Discord Bot with OpenAI ChatGPT Integration

A sophisticated Discord bot that integrates with OpenAI's ChatGPT API, featuring advanced rate limiting, usage tracking, and intelligent AI-powered responses.

## Features
# Database Configuration (Optional)
# Set DISCORD_DB_URL for PostgreSQL connection string
# This is a regular environment variable (not a secret)
# If set to "default", PostgreSQL will not be used
DISCORD_DB_URL=defaulttegration**: Full-featured Discord bot with commands and event handling
- **Advanced Rate Limiting**: Dual-layer rate limiting (messages per minute and tokens per hour)
- **Usage Tracking**: Comprehensive token usage statistics with local timezone support
- **OpenAI ChatGPT Integration**: Seamless integration with OpenAI's ChatGPT API for AI-powered responses
- **Message Filtering**: Advanced filtering system with user authorization and content safety checks
- **Sentiment Analysis**: Basic sentiment analysis of messages
- **Containerized Deployment**: Docker and Docker Compose support
- **Kubernetes Ready**: Complete Helm chart for Kubernetes deployment
- **Security Focused**: Non-root user, security contexts, and secret management

## Project Structure

```
├── discord_bot.py              # Main Discord bot application
├── message_filter.py           # Message filtering and analysis
├── openai_integration.py       # OpenAI ChatGPT integration
├── main.py                     # Entry point (Hello World or Discord bot)
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Docker container configuration
├── docker-compose.yml          # Multi-service Docker setup
├── .env.example               # Environment variables template
├── helm/                      # Helm chart for Kubernetes
│   └── discord-bot/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── README.md                  # This file
```

## Prerequisites

### For Local Development
- Python 3.11+
- pip package manager
- Discord Bot Token
- OpenAI API Key

### For Docker Deployment
- Docker and Docker Compose
- Same environment variables as local development

### For Kubernetes Deployment
- kubectl configured for your cluster
- Helm 3.x installed
- Same environment variables as local development

### For Automated Deployment (upstart.sh)
- All Kubernetes prerequisites above
- Docker installed and running
- Git repository initialized
- GitHub Personal Access Token (for container registry)
- Push access to `ghcr.io/jeffmcneely/discordai`

### 1. Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your credentials
# - Discord Bot Token
# - OpenAI API Key
# - Model settings
```

### 2. Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run simple hello world
python main.py

# Run Discord bot
python main.py --discord
```

### 3. Database Setup (Optional)

If using PostgreSQL, first create a database user for the bot, then run the database schema:

#### Create Database User
Connect to PostgreSQL as admin and create the bot user:

```sql

-- Create the discordai user with password
CREATE USER discordai WITH PASSWORD 'secretpassword';

-- Create the database (replace 'your_database_name' with your desired name)
CREATE DATABASE your_database_name OWNER discordai;

-- Grant specific permissions for the Discord bot database
-- Replace 'your_database_name' with your actual database name
GRANT CONNECT ON DATABASE your_database_name TO discordai;

-- Grant permissions on the public schema and tables
GRANT CREATE ON SCHEMA public TO discordai;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO discordai;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO discordai;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO discordai;

-- Grant permissions for future tables/sequences/functions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO discordai;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO discordai;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO discordai;
```

#### Run Database Schema
```bash
# Connect to your PostgreSQL database
psql -h your-host -U your-user -d your-database -f db.sql

# Or using environment variable (set DISCORD_DB_URL first)
export DISCORD_DB_URL="postgresql://discordai:secretpassword@your-host:5432/your-database"
psql "$DISCORD_DB_URL" -f db.sql
```

The `db.sql` file creates all necessary tables for:
- User and guild management
- Message history and analysis
- Rate limiting
- OpenAI usage tracking
- Audit logging
- User preferences and guild configuration

### 4. Configuration Setup

Before deployment, you need to configure your Discord bot with your secrets and settings:

```bash
# Set your environment variables
export DISCORD_BOT_TOKEN="your_discord_token"
export OPENAI_API_KEY="your_openai_key"
export OPENAI_MODEL="gpt-5-nano"          # Optional: defaults shown
export OPENAI_MAX_TOKENS="1000"           # Optional
export OPENAI_TEMPERATURE="0.7"           # Optional

# Create custom configuration file (this replaces Kubernetes secrets)
./deploy-config.sh

# The script creates custom-values.yaml with your environment variables
# This file is automatically excluded from Git for security
```

### 5. Automated Deployment (Recommended)

Use the `upstart.sh` script for automated build, push, and deployment:

```bash
# Make script executable (first time only)
chmod +x upstart.sh

# Run automated deployment
./upstart.sh

# Or with GitHub token for container registry
GITHUB_TOKEN=your_github_token ./upstart.sh
```

The script will:
1. Check for custom-values.yaml configuration file
2. Build the Docker image (only if source code changed)
3. Push to GitHub Container Registry (ghcr.io)
4. Deploy/update using Helm with your custom configuration
5. Show deployment status
6. Clean up build resources

### 6. Manual Kubernetes Deployment

```bash
# First, create your configuration file
./deploy-config.sh

# Then deploy with Helm using your custom values
helm install discord-bot ./helm/discord-bot \
  --values custom-values.yaml \
  --namespace discord \
  --create-namespace

# Check status
kubectl get pods -l app.kubernetes.io/name=discord-bot -n discord

# View logs
kubectl logs -l app.kubernetes.io/name=discord-bot -f -n discord
```

## Configuration

All configuration is now handled through environment variables (no Kubernetes secrets). The `deploy-config.sh` script creates a `custom-values.yaml` file that contains your configuration.

### Discord Bot Setup

1. Create a Discord application at https://discord.com/developers/applications
2. Create a bot user and copy the token
3. Invite the bot to your server with appropriate permissions:
   - Read Messages
   - Send Messages
   - Manage Messages (for moderation)
   - Add Reactions
   - View Channels

### OpenAI API Setup

1. Create an account at https://platform.openai.com/
2. Generate an API key in your account settings
3. Configure the model and parameters in your environment variables

### Configuration Files

- **`custom-values.yaml`**: Your deployment configuration (created by `deploy-config.sh`)
  - Contains environment variables for your bot
  - Automatically excluded from Git
  - Used by Helm for deployment

- **`helm/discord-bot/values.yaml`**: Default template values
  - Template file for configuration
  - Safe to commit to Git
  - Contains no secrets

### OpenAI Models and Pricing

Choose the appropriate model based on your needs and budget. All prices are per 1 million tokens:

#### GPT-4 Models (Most Capable)
| Model | Context Window | Input Cost | Output Cost | Best For |
|-------|---------------|------------|-------------|----------|
| `gpt-4o` | 128K | $5.00 | $15.00 | Latest GPT-4 with vision capabilities |
| `gpt-4o-mini` | 128K | $0.15 | $0.60 | Fast, affordable GPT-4 alternative |
| `gpt-4-turbo` | 128K | $10.00 | $30.00 | High-performance GPT-4 |
| `gpt-4` | 8K | $30.00 | $60.00 | Original GPT-4 (higher quality) |
| `gpt-4-32k` | 32K | $60.00 | $120.00 | Extended context GPT-4 |

#### GPT-3.5 Models (Fast & Cost-Effective)
| Model | Context Window | Input Cost | Output Cost | Best For |
|-------|---------------|------------|-------------|----------|
| `gpt-3.5-turbo` | 16K | $0.50 | $1.50 | General purpose, good balance |
| `gpt-3.5-turbo-16k` | 16K | $3.00 | $4.00 | Longer conversations |

#### Specialized Models
| Model | Context Window | Input Cost | Output Cost | Best For |
|-------|---------------|------------|-------------|----------|
| `text-embedding-3-small` | 8K | $0.02 | N/A | Text embeddings, semantic search |
| `text-embedding-3-large` | 8K | $0.13 | N/A | High-quality embeddings |
| `text-embedding-ada-002` | 8K | $0.10 | N/A | Legacy embedding model |

#### Cost Optimization Tips
- **For general chat**: Use `gpt-4o-mini` (best value)
- **For complex reasoning**: Use `gpt-4o` or `gpt-4-turbo`
- **For simple tasks**: Use `gpt-3.5-turbo`
- **Monitor usage**: Use the `!usage` command to track token consumption
- **Set limits**: Configure `RATE_LIMIT_TOKENS_PER_HOUR` to control costs

**Note**: Prices are subject to change. Check [OpenAI's pricing page](https://openai.com/pricing/) for the latest rates.

### Required Environment Variables

```bash
# Discord Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token

# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5-nano
OPENAI_MAX_TOKENS=1000
OPENAI_TEMPERATURE=0.7
OPENAI_INTEGRATION_ENABLED=true

# Rate Limiting Configuration
RATE_LIMIT_MESSAGES_PER_MINUTE=5
RATE_LIMIT_TOKENS_PER_HOUR=10000

# Database Configuration (Optional)
# Set DISCORD_DB_URL for PostgreSQL connection string
# Example: postgresql://username:password@host:port/database
# Or set individual POSTGRES_* variables
# If set to "default", PostgreSQL will not be used
DATABASE_URL=default
DISCORD_DB_URL=default
POSTGRES_HOST=default
POSTGRES_PORT=5432
POSTGRES_DB=default
POSTGRES_USER=default
POSTGRES_PASSWORD=default

# Optional Configuration
LOG_LEVEL=INFO
MAX_MESSAGES_PER_MINUTE=10
```

## Message Filtering

The bot includes sophisticated message filtering capabilities:

### User Authorization
- Admin privileges automatically granted
- Role-based authorization (configurable roles)
- Premium membership support
- Rate limiting per user

### Content Safety
- Blocked word filtering
- Excessive caps detection
- Special character ratio analysis
- Message length validation

### Analysis Features
- Word and character counting
- Mention and attachment detection
- Sentiment analysis
- Code and URL detection

## Bot Commands

- `!help` - Show available commands and rate limit information
- `!status` - Display bot status and statistics
- `!ping` - Check bot latency
- `!test_openai [message]` - Test OpenAI integration with a custom message
- `!openai_status` - Check OpenAI integration status
- `!usage` - Display comprehensive usage statistics including token usage, message counts, and current rate limits

## Security Features

- Non-root container execution
- Read-only root filesystem
- Dropped capabilities
- Secret management for sensitive data
- Input validation and sanitization
- Rate limiting and abuse prevention

## Monitoring and Observability

- Comprehensive logging
- Health checks for containers
- Prometheus metrics (configurable)
- Grafana dashboards (configurable)

## Development

### Adding New Features

1. **Message Filters**: Extend `MessageFilter` class in `message_filter.py`
2. **Bot Commands**: Add commands in `discord_bot.py`
3. **OpenAI Features**: Extend integration in `openai_integration.py`

### Testing

```bash
# Test OpenAI integration
python test_openai.py

# Test multi-architecture Docker build
./build-multiarch.sh

# Test Helm chart
helm template discord-bot ./helm/discord-bot
```

## Deployment Options

### Docker Compose (Recommended for Development)
- Includes Redis for caching
- Easy service management
- Connects to remote PostgreSQL if configured

### Kubernetes with Helm (Recommended for Production)
- Auto-scaling capabilities
- Service mesh integration
- Secret management
- Monitoring and observability

## Troubleshooting

### Common Issues

1. **Bot not responding**: Check Discord token and permissions
2. **OpenAI integration failing**: Verify OpenAI API key and model settings
3. **Rate limiting issues**: Adjust `RATE_LIMIT_MESSAGES_PER_MINUTE` and `RATE_LIMIT_TOKENS_PER_HOUR`
4. **Container startup issues**: Check environment variables
5. **Token usage tracking**: Use `!usage` command to monitor consumption

### Logs

```bash
# Docker Compose logs
docker-compose logs discord-bot

# Kubernetes logs
kubectl logs -l app.kubernetes.io/name=discord-bot

# Local development
python main.py --discord  # Logs to console
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the GitHub repository
- Check the troubleshooting section
- Review logs for error details
