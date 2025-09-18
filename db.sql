-- Discord Bot Database Schema
-- This file contains the SQL commands to create all necessary tables for the Discord bot

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table for storing Discord user information
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    discord_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(255) NOT NULL,
    discriminator VARCHAR(4),
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Guilds table for storing Discord server information
CREATE TABLE IF NOT EXISTS guilds (
    id SERIAL PRIMARY KEY,
    discord_id BIGINT UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    icon_url TEXT,
    member_count INTEGER DEFAULT 0,
    owner_id BIGINT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User-Guild relationship table
CREATE TABLE IF NOT EXISTS user_guilds (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    roles TEXT[], -- Array of role IDs
    nickname VARCHAR(255),
    UNIQUE(user_id, guild_id)
);

-- Messages table for storing message history and analysis
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    discord_id BIGINT UNIQUE NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    channel_id BIGINT NOT NULL,
    content TEXT,
    message_type VARCHAR(50) DEFAULT 'text',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    attachments JSONB DEFAULT '[]',
    embeds JSONB DEFAULT '[]',
    mentions JSONB DEFAULT '{}',
    reactions JSONB DEFAULT '[]'
);

-- Message analysis table for storing AI analysis results
CREATE TABLE IF NOT EXISTS message_analysis (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    sentiment VARCHAR(20),
    sentiment_score DECIMAL(3,2),
    toxicity_score DECIMAL(3,2),
    content_filter_flags TEXT[],
    word_count INTEGER,
    character_count INTEGER,
    language VARCHAR(10) DEFAULT 'en',
    analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ai_model VARCHAR(100),
    analysis_metadata JSONB DEFAULT '{}'
);

-- Rate limiting table for tracking user activity
CREATE TABLE IF NOT EXISTS rate_limits (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    action_type VARCHAR(50) NOT NULL, -- 'message', 'command', etc.
    count INTEGER DEFAULT 1,
    window_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    window_end TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, guild_id, action_type, window_start)
);

-- Commands table for tracking bot command usage
CREATE TABLE IF NOT EXISTS commands (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    command_name VARCHAR(100) NOT NULL,
    args TEXT,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    execution_time_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- OpenAI usage tracking table
CREATE TABLE IF NOT EXISTS openai_usage (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    model VARCHAR(100) NOT NULL,
    tokens_used INTEGER NOT NULL,
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    cost_cents INTEGER DEFAULT 0, -- Cost in cents
    request_type VARCHAR(50) DEFAULT 'chat', -- 'chat', 'completion', 'embedding', etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User preferences table
CREATE TABLE IF NOT EXISTS user_preferences (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    preference_key VARCHAR(100) NOT NULL,
    preference_value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, preference_key)
);

-- Bot configuration table for per-guild settings
CREATE TABLE IF NOT EXISTS guild_config (
    id SERIAL PRIMARY KEY,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    config_key VARCHAR(100) NOT NULL,
    config_value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(guild_id, config_key)
);

-- Audit log table for important bot actions
CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    guild_id INTEGER REFERENCES guilds(id) ON DELETE CASCADE,
    action VARCHAR(100) NOT NULL,
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_users_discord_id ON users(discord_id);
CREATE INDEX IF NOT EXISTS idx_guilds_discord_id ON guilds(discord_id);
CREATE INDEX IF NOT EXISTS idx_messages_discord_id ON messages(discord_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_guild_id ON messages(guild_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_message_analysis_message_id ON message_analysis(message_id);
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_window ON rate_limits(user_id, window_start);
CREATE INDEX IF NOT EXISTS idx_commands_user_created ON commands(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_openai_usage_user_created ON openai_usage(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at columns
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guilds_updated_at BEFORE UPDATE ON guilds
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_preferences_updated_at BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guild_config_updated_at BEFORE UPDATE ON guild_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to clean up old rate limit entries
CREATE OR REPLACE FUNCTION cleanup_old_rate_limits()
RETURNS void AS $$
BEGIN
    DELETE FROM rate_limits
    WHERE window_end < CURRENT_TIMESTAMP - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Comments for documentation
COMMENT ON TABLE users IS 'Discord users that have interacted with the bot';
COMMENT ON TABLE guilds IS 'Discord servers/guilds where the bot is active';
COMMENT ON TABLE messages IS 'Stored Discord messages for analysis and history';
COMMENT ON TABLE message_analysis IS 'AI analysis results for messages';
COMMENT ON TABLE rate_limits IS 'Rate limiting data for users and guilds';
COMMENT ON TABLE commands IS 'Bot command usage tracking';
COMMENT ON TABLE openai_usage IS 'OpenAI API usage tracking and costs';
COMMENT ON TABLE user_preferences IS 'User-specific bot preferences';
COMMENT ON TABLE guild_config IS 'Per-guild bot configuration';
COMMENT ON TABLE audit_log IS 'Audit trail for important bot actions';

-- Insert default guild configuration
INSERT INTO guild_config (guild_id, config_key, config_value)
SELECT DISTINCT g.id, 'max_messages_per_minute', '5'
FROM guilds g
WHERE NOT EXISTS (
    SELECT 1 FROM guild_config gc
    WHERE gc.guild_id = g.id AND gc.config_key = 'max_messages_per_minute'
);

INSERT INTO guild_config (guild_id, config_key, config_value)
SELECT DISTINCT g.id, 'max_tokens_per_hour', '10000'
FROM guilds g
WHERE NOT EXISTS (
    SELECT 1 FROM guild_config gc
    WHERE gc.guild_id = g.id AND gc.config_key = 'max_tokens_per_hour'
);

-- Create a view for user statistics
CREATE OR REPLACE VIEW user_stats AS
SELECT
    u.id,
    u.discord_id,
    u.username,
    u.discriminator,
    COUNT(DISTINCT ug.guild_id) as guild_count,
    COUNT(m.id) as total_messages,
    COUNT(CASE WHEN m.created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 1 END) as messages_24h,
    COALESCE(SUM(ou.tokens_used), 0) as total_tokens_used,
    MAX(m.created_at) as last_message_at
FROM users u
LEFT JOIN user_guilds ug ON u.id = ug.user_id
LEFT JOIN messages m ON u.id = m.user_id
LEFT JOIN openai_usage ou ON u.id = ou.user_id
GROUP BY u.id, u.discord_id, u.username, u.discriminator;

-- Grant permissions (adjust as needed for your application)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO discord_bot_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO discord_bot_user;