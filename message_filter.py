"""
Message Filter Module for Discord Bot
Analyzes Discord messages and user permissions for OpenAI integration
"""

import discord
import logging
import os
from typing import Dict, Any, List
import re
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

class MessageFilter:
    """Filters and analyzes Discord messages for processing"""
    
    def __init__(self):
        self.authorized_roles = [
            'admin', 'moderator', 'openai-user', 'premium'
        ]
        self.blocked_words = [
            'spam', 'inappropriate', 'offensive'  # Add your blocked words
        ]
        self.rate_limit = {}  # User rate limiting: {user_id: {'messages': [(timestamp, token_count)], 'tokens_used': total}}
        # Get rate limits from environment variables
        self.max_messages_per_minute = int(os.getenv('RATE_LIMIT_MESSAGES_PER_MINUTE', '5'))
        self.max_tokens_per_hour = int(os.getenv('RATE_LIMIT_TOKENS_PER_HOUR', '10000'))
    
    async def analyze_message(self, message: discord.Message) -> Dict[str, Any]:
        """
        Analyze a Discord message and determine if it should be processed
        
        Args:
            message: Discord message object
            
        Returns:
            Dict containing analysis results
        """
        result = {
            'should_process': False,
            'user_authorized': False,
            'content_safe': False,
            'rate_limited': False,
            'analysis': {},
            'timestamp': datetime.utcnow()
        }
        
        try:
            # Check user authorization
            result['user_authorized'] = await self._check_user_authorization(message.author)
            
            # Check content safety
            result['content_safe'] = await self._check_content_safety(message.content)
            
            # Check rate limiting
            result['rate_limited'] = await self._check_rate_limit(message.author)
            
            # Perform message analysis
            result['analysis'] = await self._analyze_message_content(message)
            
            # Determine if message should be processed
            result['should_process'] = (
                result['user_authorized'] and 
                result['content_safe'] and 
                not result['rate_limited'] and
                len(message.content.strip()) > 0
            )
            
            logger.info(f"Message analysis for {message.author}: {result['should_process']}")
            
        except Exception as e:
            logger.error(f"Error analyzing message: {e}")
            result['should_process'] = False
        
        return result
    
    async def _check_user_authorization(self, user: discord.Member) -> bool:
        """Check if user is authorized to use Copilot integration"""
        try:
            # Check if user has authorized roles
            if user.guild_permissions.administrator:
                return True
            
            user_roles = [role.name.lower() for role in user.roles]
            
            for authorized_role in self.authorized_roles:
                if authorized_role in user_roles:
                    return True
            
            # Check premium membership or other criteria
            if user.premium_since:
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Error checking user authorization: {e}")
            return False
    
    async def _check_content_safety(self, content: str) -> bool:
        """Check if message content is safe for processing"""
        try:
            content_lower = content.lower()
            
            # Check for blocked words
            for blocked_word in self.blocked_words:
                if blocked_word in content_lower:
                    return False
            
            # Check for excessive caps
            if len(content) > 10 and content.isupper():
                return False
            
            # Check for excessive special characters
            special_char_ratio = len(re.findall(r'[!@#$%^&*()_+\-=\[\]{};\':"\\|,.<>\?]', content)) / len(content)
            if special_char_ratio > 0.3:
                return False
            
            # Check message length
            if len(content) > 2000:  # Discord's message limit
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error checking content safety: {e}")
            return False
    
    async def _check_rate_limit(self, user: discord.Member) -> bool:
        """Check if user is rate limited (both message count and token usage)"""
        try:
            user_id = user.id
            current_time = datetime.utcnow()
            
            # Initialize user rate limit tracking
            if user_id not in self.rate_limit:
                self.rate_limit[user_id] = {
                    'messages': [],  # List of (timestamp, token_count) tuples
                    'tokens_used_hour': 0,
                    'last_hour_reset': current_time
                }
            
            user_data = self.rate_limit[user_id]
            
            # Reset hourly token count if an hour has passed
            if current_time - user_data['last_hour_reset'] >= timedelta(hours=1):
                user_data['tokens_used_hour'] = 0
                user_data['last_hour_reset'] = current_time
            
            # Remove old message timestamps (older than 1 minute)
            user_data['messages'] = [
                (timestamp, tokens) for timestamp, tokens in user_data['messages']
                if current_time - timestamp < timedelta(minutes=1)
            ]
            
            # Check message rate limit (messages per minute)
            message_count = len(user_data['messages'])
            if message_count >= self.max_messages_per_minute:
                logger.info(f"User {user.name} rate limited: {message_count}/{self.max_messages_per_minute} messages per minute")
                return True  # Rate limited by message count
            
            # Check token rate limit (tokens per hour)
            if user_data['tokens_used_hour'] >= self.max_tokens_per_hour:
                logger.info(f"User {user.name} rate limited: {user_data['tokens_used_hour']}/{self.max_tokens_per_hour} tokens per hour")
                return True  # Rate limited by token usage
            
            # Add current message (we'll update token count later in OpenAI integration)
            user_data['messages'].append((current_time, 0))  # 0 tokens for now, will be updated
            
            return False  # Not rate limited
            
        except Exception as e:
            logger.error(f"Error checking rate limit: {e}")
            return True  # Err on the side of caution
    
    async def _analyze_message_content(self, message: discord.Message) -> Dict[str, Any]:
        """Analyze message content for additional insights"""
        try:
            analysis = {
                'word_count': len(message.content.split()),
                'character_count': len(message.content),
                'has_mentions': len(message.mentions) > 0,
                'has_attachments': len(message.attachments) > 0,
                'has_embeds': len(message.embeds) > 0,
                'channel_type': str(message.channel.type),
                'channel_name': message.channel.name if hasattr(message.channel, 'name') else 'DM',
                'guild_name': message.guild.name if message.guild else 'DM',
                'is_reply': message.reference is not None,
                'contains_code': '```' in message.content,
                'contains_url': bool(re.search(r'https?://', message.content)),
                'sentiment': await self._analyze_sentiment(message.content)
            }
            
            return analysis
            
        except Exception as e:
            logger.error(f"Error analyzing message content: {e}")
            return {}
    
    async def _analyze_sentiment(self, content: str) -> str:
        """Basic sentiment analysis"""
        try:
            positive_words = ['good', 'great', 'excellent', 'awesome', 'love', 'like', 'happy']
            negative_words = ['bad', 'terrible', 'awful', 'hate', 'dislike', 'sad', 'angry']
            
            content_lower = content.lower()
            positive_count = sum(1 for word in positive_words if word in content_lower)
            negative_count = sum(1 for word in negative_words if word in content_lower)
            
            if positive_count > negative_count:
                return 'positive'
            elif negative_count > positive_count:
                return 'negative'
            else:
                return 'neutral'
                
        except Exception as e:
            logger.error(f"Error analyzing sentiment: {e}")
            return 'neutral'
    
    def update_token_usage(self, user_id: int, token_count: int):
        """Update token usage for a user after OpenAI API call"""
        try:
            if user_id in self.rate_limit:
                # Update the most recent message's token count
                if self.rate_limit[user_id]['messages']:
                    timestamp, _ = self.rate_limit[user_id]['messages'][-1]
                    self.rate_limit[user_id]['messages'][-1] = (timestamp, token_count)
                
                # Update hourly token usage
                self.rate_limit[user_id]['tokens_used_hour'] += token_count
                
                logger.debug(f"Updated token usage for user {user_id}: +{token_count} tokens")
        except Exception as e:
            logger.error(f"Error updating token usage: {e}")
    
    def get_user_usage_stats(self, user_id: int) -> Dict[str, Any]:
        """Get usage statistics for a user"""
        try:
            current_time = datetime.utcnow()
            
            if user_id not in self.rate_limit:
                return {
                    'messages_this_minute': 0,
                    'tokens_this_hour': 0,
                    'total_messages': 0,
                    'total_tokens': 0,
                    'rate_limit_status': 'OK'
                }
            
            user_data = self.rate_limit[user_id]
            
            # Count recent messages
            recent_messages = [
                (timestamp, tokens) for timestamp, tokens in user_data['messages']
                if current_time - timestamp < timedelta(minutes=1)
            ]
            
            # Calculate total tokens from all messages in history
            total_tokens = sum(tokens for _, tokens in user_data['messages'])
            
            # Determine rate limit status
            status = 'OK'
            if len(recent_messages) >= self.max_messages_per_minute:
                status = 'MESSAGE_RATE_LIMITED'
            elif user_data['tokens_used_hour'] >= self.max_tokens_per_hour:
                status = 'TOKEN_RATE_LIMITED'
            
            return {
                'messages_this_minute': len(recent_messages),
                'tokens_this_hour': user_data['tokens_used_hour'],
                'total_messages': len(user_data['messages']),
                'total_tokens': total_tokens,
                'rate_limit_status': status,
                'max_messages_per_minute': self.max_messages_per_minute,
                'max_tokens_per_hour': self.max_tokens_per_hour
            }
            
        except Exception as e:
            logger.error(f"Error getting usage stats: {e}")
            return {'error': str(e)}
    
    def add_authorized_role(self, role_name: str):
        """Add a role to the authorized roles list"""
        if role_name.lower() not in self.authorized_roles:
            self.authorized_roles.append(role_name.lower())
    
    def remove_authorized_role(self, role_name: str):
        """Remove a role from the authorized roles list"""
        if role_name.lower() in self.authorized_roles:
            self.authorized_roles.remove(role_name.lower())
    
    def add_blocked_word(self, word: str):
        """Add a word to the blocked words list"""
        if word.lower() not in self.blocked_words:
            self.blocked_words.append(word.lower())
    
    def remove_blocked_word(self, word: str):
        """Remove a word from the blocked words list"""
        if word.lower() in self.blocked_words:
            self.blocked_words.remove(word.lower())
