#!/usr/bin/env python3
"""
Discord Bot with Message Filtering and OpenAI ChatGPT Integration
"""

import discord
from discord.ext import commands
import os
import logging
from datetime import datetime
from dotenv import load_dotenv
from message_filter import MessageFilter
from openai_integration import OpenAIIntegration

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DiscordBot(commands.Bot):
    """Discord Bot with message filtering and OpenAI integration"""
    
    def __init__(self):
        intents = discord.Intents.default()
        intents.message_content = True
        intents.members = True
        
        super().__init__(
            command_prefix='!',
            intents=intents,
            help_command=None
        )
        
        self.message_filter = MessageFilter()
        self.openai_integration = OpenAIIntegration(message_filter=self.message_filter)
    
    async def on_ready(self):
        """Called when the bot is ready"""
        logger.info(f'{self.user} has connected to Discord!')
        logger.info(f'Bot is in {len(self.guilds)} guilds')
        
        # Set bot status
        await self.change_presence(
            activity=discord.Activity(
                type=discord.ActivityType.watching,
                name="for messages | !help"
            )
        )
    
    async def on_message(self, message):
        """Handle incoming messages"""
        # Don't respond to ourselves
        if message.author == self.user:
            return
        
        # Don't send commands to OpenAI (messages starting with command prefix)
        is_command = message.content.startswith(self.command_prefix)
        
        # Filter and analyze the message (but skip commands)
        if not is_command:
            try:
                filter_result = await self.message_filter.analyze_message(message)
                
                if filter_result['should_process']:
                    # Send to OpenAI ChatGPT if authorized
                    await self.openai_integration.relay_message(message, filter_result)
                
            except Exception as e:
                logger.error(f"Error processing message: {e}")
        
        # Process commands
        await self.process_commands(message)
    
    async def on_member_join(self, member):
        """Welcome new members"""
        logger.info(f'{member} has joined {member.guild}')
        
        # Send welcome message to system channel if available
        if member.guild.system_channel:
            embed = discord.Embed(
                title="Welcome!",
                description=f"Welcome to {member.guild.name}, {member.mention}!",
                color=0x00ff00
            )
            await member.guild.system_channel.send(embed=embed)
    
    async def on_command_error(self, ctx, error):
        """Handle command errors"""
        if isinstance(error, commands.CommandNotFound):
            await ctx.send("Command not found. Use `!help` for available commands.")
        else:
            logger.error(f"Command error: {error}")
            await ctx.send("An error occurred while processing the command.")

# Bot commands
@commands.command(name='help')
async def help_command(ctx):
    """Show help information"""
    embed = discord.Embed(
        title="Discord Bot Commands",
        description="Available commands:",
        color=0x0099ff
    )
    embed.add_field(
        name="!help",
        value="Show this help message",
        inline=False
    )
    embed.add_field(
        name="!status",
        value="Check bot status",
        inline=False
    )
    embed.add_field(
        name="!ping",
        value="Check bot latency",
        inline=False
    )
    embed.add_field(
        name="!test_openai [message]",
        value="Test OpenAI ChatGPT integration with a custom message",
        inline=False
    )
    embed.add_field(
        name="!openai_status",
        value="Check OpenAI integration status",
        inline=False
    )
    embed.add_field(
        name="!usage",
        value="Show OpenAI token usage statistics and rate limits",
        inline=False
    )
    await ctx.send(embed=embed)

@commands.command(name='status')
async def status_command(ctx):
    """Show bot status"""
    embed = discord.Embed(
        title="Bot Status",
        color=0x00ff00
    )
    embed.add_field(
        name="Guilds",
        value=str(len(ctx.bot.guilds)),
        inline=True
    )
    embed.add_field(
        name="Latency",
        value=f"{round(ctx.bot.latency * 1000)}ms",
        inline=True
    )
    await ctx.send(embed=embed)

@commands.command(name='ping')
async def ping_command(ctx):
    """Check bot latency"""
    latency = round(ctx.bot.latency * 1000)
    await ctx.send(f'Pong! Latency: {latency}ms')

@commands.command(name='test_openai')
async def test_openai_command(ctx, *, message="Hello ChatGPT!"):
    """Test the OpenAI integration with a sample message"""
    try:
        # Create a mock filter result for testing
        filter_result = {
            'should_process': True,
            'user_authorized': True,
            'content_safe': True,
            'rate_limited': False,
            'analysis': {
                'word_count': len(message.split()),
                'sentiment': 'neutral'
            }
        }
        
        # Create a mock message for testing
        test_message = type('TestMessage', (), {
            'content': message,
            'author': ctx.author,
            'channel': ctx.channel,
            'guild': ctx.guild,
            'id': 999999999,
            'created_at': ctx.message.created_at,
            'mentions': [],
            'attachments': [],
            'embeds': [],
            'reference': None
        })()
        
        await ctx.send(f"🧪 Testing OpenAI with message: `{message}`")
        await ctx.bot.openai_integration.relay_message(test_message, filter_result)
        
    except Exception as e:
        await ctx.send(f"❌ Error testing OpenAI: {e}")

@commands.command(name='openai_status')
async def openai_status_command(ctx):
    """Check OpenAI integration status"""
    openai = ctx.bot.openai_integration
    
    embed = discord.Embed(
        title="🤖 OpenAI ChatGPT Integration Status",
        color=0x00A67E
    )
    
    embed.add_field(
        name="Enabled",
        value="✅ Yes" if openai.enabled else "❌ No",
        inline=True
    )
    
    embed.add_field(
        name="Model",
        value=openai.openai_model,
        inline=True
    )
    
    embed.add_field(
        name="API Key Configured",
        value="✅ Yes" if openai.openai_api_key and openai.openai_api_key != "your-openai-api-key-here" else "❌ No",
        inline=True
    )
    
    embed.add_field(
        name="Max Tokens",
        value=str(openai.max_tokens),
        inline=True
    )
    
    embed.add_field(
        name="Temperature",
        value=str(openai.temperature),
        inline=True
    )
    
    embed.add_field(
        name="Endpoint",
        value=openai.openai_endpoint,
        inline=False
    )
    
    await ctx.send(embed=embed)

@commands.command(name='usage')
async def usage_command(ctx):
    """Show OpenAI token usage statistics"""
    try:
        openai = ctx.bot.openai_integration
        message_filter = ctx.bot.message_filter
        
        # Get overall statistics
        overall_stats = openai.get_usage_statistics()
        
        # Get user-specific statistics
        user_stats = message_filter.get_user_usage_stats(ctx.author.id)
        
        embed = discord.Embed(
            title="📊 OpenAI Usage Statistics",
            color=0x00A67E,
            timestamp=datetime.utcnow()
        )
        
        # Overall session statistics
        embed.add_field(
            name="🌐 Session Statistics",
            value=(
                f"**Total Tokens Used:** {overall_stats.get('total_tokens_used', 0):,}\n"
                f"**API Calls Made:** {overall_stats.get('api_calls_made', 0):,}\n"
                f"**Session Duration:** {overall_stats.get('session_duration_hours', 0):.1f} hours\n"
                f"**Average Tokens/Call:** {overall_stats.get('average_tokens_per_call', 0):.1f}\n"
                f"**Tokens/Hour:** {overall_stats.get('tokens_per_hour', 0):.1f}"
            ),
            inline=False
        )
        
        # User-specific statistics
        embed.add_field(
            name=f"👤 Your Usage ({ctx.author.display_name})",
            value=(
                f"**Messages This Minute:** {user_stats.get('messages_this_minute', 0)}/{user_stats.get('max_messages_per_minute', 5)}\n"
                f"**Tokens This Hour:** {user_stats.get('tokens_this_hour', 0):,}/{user_stats.get('max_tokens_per_hour', 10000):,}\n"
                f"**Total Messages:** {user_stats.get('total_messages', 0):,}\n"
                f"**Total Tokens:** {user_stats.get('total_tokens', 0):,}\n"
                f"**Status:** {user_stats.get('rate_limit_status', 'Unknown')}"
            ),
            inline=False
        )
        
        # Configuration information
        embed.add_field(
            name="⚙️ Configuration",
            value=(
                f"**Model:** {overall_stats.get('model', 'Unknown')}\n"
                f"**Max Tokens/Request:** {overall_stats.get('max_tokens_per_request', 0):,}\n"
                f"**Temperature:** {overall_stats.get('temperature', 0)}\n"
                f"**Integration Enabled:** {'✅ Yes' if overall_stats.get('integration_enabled', False) else '❌ No'}"
            ),
            inline=False
        )
        
        # Rate limit warnings
        if user_stats.get('rate_limit_status') != 'OK':
            if user_stats.get('rate_limit_status') == 'MESSAGE_RATE_LIMITED':
                embed.add_field(
                    name="⚠️ Rate Limit Warning",
                    value="You've reached the message rate limit. Please wait before sending more messages.",
                    inline=False
                )
            elif user_stats.get('rate_limit_status') == 'TOKEN_RATE_LIMITED':
                embed.add_field(
                    name="⚠️ Token Limit Warning", 
                    value="You've reached the hourly token limit. Your limit will reset in the next hour.",
                    inline=False
                )
        
        embed.set_footer(text=f"Session started: {overall_stats.get('session_start', 'Unknown')}")
        
        await ctx.send(embed=embed)
        
    except Exception as e:
        logger.error(f"Error in usage command: {e}")
        await ctx.send(f"❌ Error retrieving usage statistics: {e}")

def main():
    """Main function to run the bot"""
    # Get Discord token from environment
    token = os.getenv('DISCORD_BOT_TOKEN')
    
    if not token:
        logger.error("DISCORD_BOT_TOKEN not found in environment variables")
        return
    
    # Create and run bot
    bot = DiscordBot()
    
    # Add commands to bot
    bot.add_command(help_command)
    bot.add_command(status_command)
    bot.add_command(ping_command)
    bot.add_command(test_openai_command)
    bot.add_command(openai_status_command)
    bot.add_command(usage_command)
    
    try:
        bot.run(token)
    except Exception as e:
        logger.error(f"Failed to start bot: {e}")

if __name__ == "__main__":
    main()
