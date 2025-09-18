"""
OpenAI ChatGPT Integration Module
Handles relaying Discord messages to OpenAI ChatGPT API
"""

import discord
import aiohttp
import logging
import os
import json
from typing import Dict, Any, List
from datetime import datetime, timezone, timedelta
import time

logger = logging.getLogger(__name__)

class OpenAIIntegration:
    """Integrates with OpenAI ChatGPT API for message processing"""
    
    def __init__(self, message_filter=None):
        self.openai_api_key = os.getenv('OPENAI_API_KEY')
        self.openai_model = os.getenv('OPENAI_MODEL', 'gpt-5-nano')
        self.openai_endpoint = os.getenv('OPENAI_ENDPOINT', 'https://api.openai.com/v1/chat/completions')
        self.max_tokens = int(os.getenv('OPENAI_MAX_TOKENS', '500'))
        self.temperature = float(os.getenv('OPENAI_TEMPERATURE', '0.7'))
        self.enabled = os.getenv('OPENAI_INTEGRATION_ENABLED', 'true').lower() == 'true'
        
        # Reference to message filter for token tracking
        self.message_filter = message_filter
        
        # Session for HTTP requests
        self.session = None
        
        # Token usage tracking
        self.total_tokens_used = 0
        self.api_calls_made = 0
        self.session_start = datetime.utcnow()
        
        # Temporary user model preferences (user_id -> {'model': str, 'expires_at': datetime})
        self.user_models = {}
        
        if not self.enabled:
            logger.info("OpenAI integration disabled via OPENAI_INTEGRATION_ENABLED=false")
        elif not self.openai_api_key or self.openai_api_key == "your-openai-api-key-here":
            logger.error("OpenAI API key not configured - integration will not work")
    
    def set_user_model(self, user_id: int, model: str, duration_hours: int = 1):
        """Set a temporary model preference for a user"""
        expires_at = datetime.now(timezone.utc) + timedelta(hours=duration_hours)
        self.user_models[user_id] = {
            'model': model,
            'expires_at': expires_at
        }
        logger.info(f"Set temporary model '{model}' for user {user_id}, expires at {expires_at}")
    
    def get_user_model(self, user_id: int) -> str:
        """Get the current model for a user (temporary or default)"""
        # Clean up expired models first
        self._cleanup_expired_models()
        
        if user_id in self.user_models:
            return self.user_models[user_id]['model']
        return self.openai_model
    
    def _cleanup_expired_models(self):
        """Remove expired temporary model preferences"""
        now = datetime.now(timezone.utc)
        expired_users = [
            user_id for user_id, data in self.user_models.items()
            if data['expires_at'] <= now
        ]
        for user_id in expired_users:
            logger.info(f"Removing expired temporary model for user {user_id}")
            del self.user_models[user_id]
    
    def get_user_model_info(self, user_id: int) -> Dict[str, Any]:
        """Get information about a user's current model preference"""
        self._cleanup_expired_models()
        
        if user_id in self.user_models:
            data = self.user_models[user_id]
            return {
                'model': data['model'],
                'expires_at': data['expires_at'],
                'is_temporary': True,
                'time_remaining': data['expires_at'] - datetime.now(timezone.utc)
            }
        return {
            'model': self.openai_model,
            'is_temporary': False
        }
    
    async def _get_session(self):
        """Get or create aiohttp session"""
        if self.session is None:
            self.session = aiohttp.ClientSession()
        return self.session
    
    async def relay_message(self, message: discord.Message, filter_result: Dict[str, Any]):
        """
        Relay filtered Discord message to OpenAI ChatGPT API
        
        Args:
            message: Discord message object
            filter_result: Results from message filtering
        """
        try:
            logger.info(f"📩 OPENAI RELAY REQUEST: '{message.content[:100]}{'...' if len(message.content) > 100 else ''}' from {message.author.name}")
            
            if not self.enabled:
                logger.debug("❌ OpenAI integration disabled - skipping message relay")
                return
                
            if not self.openai_api_key or self.openai_api_key == "your-openai-api-key-here":
                logger.error("❌ OpenAI API key not configured")
                return
                
            if not filter_result.get('should_process', False):
                logger.info(f"❌ Message filtered out - should_process: {filter_result.get('should_process')}")
                logger.debug(f"Filter details: authorized={filter_result.get('user_authorized')}, safe={filter_result.get('content_safe')}, rate_limited={filter_result.get('rate_limited')}")
                return
            
            logger.info("✅ Message passed filter, preparing for OpenAI...")
            
            # Prepare message for ChatGPT API
            chat_messages = await self._prepare_chat_messages(message, filter_result)
            logger.debug(f"📝 Prepared {len(chat_messages)} chat messages")
            
            # Send to OpenAI ChatGPT API
            logger.info("🚀 Sending to OpenAI ChatGPT...")
            response = await self._send_to_openai(chat_messages, message.author.id)
            
            # Process ChatGPT response if available
            if response:
                logger.info("📨 Received response from ChatGPT, processing...")
                await self._handle_openai_response(message, response)
            else:
                logger.warning("⚠️ No response received from OpenAI")
            
        except Exception as e:
            logger.error(f"Error relaying message to OpenAI: {e}")
    
    async def _prepare_chat_messages(self, message: discord.Message, filter_result: Dict[str, Any]) -> List[Dict[str, str]]:
        """Prepare messages for OpenAI ChatGPT API format"""
        try:
            # System message to set the context
            system_message = {
                "role": "system",
                "content": (
                    "You are a helpful AI assistant integrated into a Discord server. "
                    "Provide helpful, friendly, and concise responses to user messages. "
                    "Keep responses conversational and appropriate for a Discord chat environment. "
                    f"The user's name is {message.author.display_name}. "
                    f"This message is from the #{message.channel.name if hasattr(message.channel, 'name') else 'DM'} channel."
                )
            }
            
            # User message
            user_message = {
                "role": "user",
                "content": message.content
            }
            
            # Return messages array
            messages = [system_message, user_message]
            
            return messages
            
        except Exception as e:
            logger.error(f"Error preparing chat messages: {e}")
            return []
    
    async def _send_to_openai(self, messages: List[Dict[str, str]], user_id: int = None) -> Dict[str, Any]:
        """Send messages to OpenAI ChatGPT API"""
        try:
            if not messages:
                logger.warning("No messages to send to OpenAI")
                return None
            
            session = await self._get_session()
            
            # Get the appropriate model for this user
            model_to_use = self.get_user_model(user_id) if user_id else self.openai_model
            
            headers = {
                'Authorization': f'Bearer {self.openai_api_key}',
                'Content-Type': 'application/json'
            }
            
            # Base payload
            payload = {
                'model': model_to_use,
                'messages': messages
            }
            
            # Add temperature only for models that support it
            # gpt-5-nano and some other models only support default temperature (1.0)
            models_with_fixed_temperature = ['gpt-5-nano', 'gpt-o1', 'o1-preview', 'o1-mini']
            
            if not any(model_name in model_to_use.lower() for model_name in models_with_fixed_temperature):
                payload['temperature'] = self.temperature
            else:
                logger.debug(f"Model {model_to_use} uses fixed temperature, skipping temperature parameter")
            
            # Add the appropriate token limit parameter based on model
            if model_to_use.startswith('gpt-5') or model_to_use.startswith('o'):
                payload['max_completion_tokens'] = self.max_tokens
            else:
                payload['max_tokens'] = self.max_tokens
            
            logger.debug(f"Sending to OpenAI: {json.dumps(payload, indent=2)}")
            
            async with session.post(
                self.openai_endpoint,
                headers=headers,
                json=payload
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"✅ OpenAI API response received successfully")
                    return result
                else:
                    error_text = await response.text()
                    logger.error(f"❌ OpenAI API error: {response.status} - {error_text}")
                    return None
                    
        except Exception as e:
            logger.error(f"Error sending to OpenAI: {e}")
            return None
    
    async def _handle_openai_response(self, original_message: discord.Message, openai_response: Dict[str, Any]):
        """
        Handle response from OpenAI ChatGPT and relay back to Discord
        
        Args:
            original_message: Original Discord message
            openai_response: Response from OpenAI API
        """
        try:
            logger.info(f"🤖 OPENAI RESPONSE HANDLER: Processing response for '{original_message.content[:50]}{'...' if len(original_message.content) > 50 else ''}'")
            
            # Extract response content from OpenAI format
            choices = openai_response.get('choices', [])
            if not choices:
                logger.warning("No choices in OpenAI response")
                return
            
            response_content = choices[0].get('message', {}).get('content', '')
            finish_reason = choices[0].get('finish_reason', 'unknown')
            
            # Extract usage information and update tracking
            usage = openai_response.get('usage', {})
            total_tokens = usage.get('total_tokens', 0)
            prompt_tokens = usage.get('prompt_tokens', 0)
            completion_tokens = usage.get('completion_tokens', 0)
            
            # Update global tracking
            self.total_tokens_used += total_tokens
            self.api_calls_made += 1
            
            # Update user's token usage in message filter
            if self.message_filter:
                self.message_filter.update_token_usage(original_message.author.id, total_tokens)
            
            # Convert OpenAI timestamp to local time if available
            created_timestamp = openai_response.get('created')
            if created_timestamp:
                # Convert Unix timestamp to local datetime
                local_time = datetime.fromtimestamp(created_timestamp, tz=timezone.utc).astimezone()
                timestamp_str = local_time.strftime("%Y-%m-%d %H:%M:%S %Z")
            else:
                local_time = datetime.now()
                timestamp_str = local_time.strftime("%Y-%m-%d %H:%M:%S")
            
            logger.info(f"📊 Response details: finish_reason='{finish_reason}', length={len(response_content)}")
            logger.info(f"📈 Token usage: prompt={prompt_tokens}, completion={completion_tokens}, total={total_tokens}")
            logger.info(f"🕐 Response generated at: {timestamp_str}")
            
            if not response_content:
                logger.warning("Empty response content from OpenAI")
                return
            
            # Create Discord embed for better presentation
            embed = discord.Embed(
                title="🤖 ChatGPT Response",
                description=response_content,
                color=0x00A67E,  # OpenAI green
                timestamp=local_time
            )
            
            embed.add_field(
                name="💬 Responding to", 
                value=f"{original_message.author.mention}: {original_message.content[:100]}{'...' if len(original_message.content) > 100 else ''}", 
                inline=False
            )
            
            embed.add_field(name="🧠 Model", value=self.openai_model, inline=True)
            embed.add_field(name="🎛️ Temperature", value=f"{self.temperature}", inline=True)
            embed.add_field(name="📊 Tokens", value=f"{usage.get('total_tokens', 'N/A')}", inline=True)
            
            embed.set_footer(
                text=f"Powered by OpenAI • Requested by {original_message.author.display_name}",
                icon_url=original_message.author.avatar.url if original_message.author.avatar else None
            )
            
            logger.info("📝 Created Discord embed with ChatGPT response")
            
            # Send response to Discord
            sent_message = await original_message.channel.send(embed=embed)
            logger.info(f"✅ RESPONSE SENT: Message ID {sent_message.id} sent to #{original_message.channel.name}")
            logger.info(f"📈 OPENAI METRICS: Model='{self.openai_model}', Tokens={usage.get('total_tokens', 0)}, Channel='{original_message.channel.name}', User='{original_message.author.name}'")
            
        except discord.HTTPException as e:
            logger.error(f"❌ Discord HTTP error sending response: {e}")
            # Fallback: send simple text message
            try:
                fallback_msg = f"🤖 **ChatGPT:** {response_content[:1500]}{'...' if len(response_content) > 1500 else ''}"
                await original_message.channel.send(fallback_msg)
                logger.info("🔄 Sent fallback text response due to embed error")
            except Exception as fallback_error:
                logger.error(f"❌ Critical: Failed to send even fallback response: {fallback_error}")
                
        except Exception as e:
            logger.error(f"❌ Unexpected error in OpenAI response handler: {e}")
            logger.error(f"Error details: Type={type(e).__name__}, Args={e.args}")
            # Attempt to send error notification
            try:
                error_msg = "🚨 I encountered an unexpected error while processing your request. The development team has been notified."
                await original_message.channel.send(error_msg)
                logger.info("📧 Sent error notification message to user")
            except Exception as critical_error:
                logger.critical(f"💀 CRITICAL: Cannot send any response to Discord: {critical_error}")
    
    def get_usage_statistics(self) -> Dict[str, Any]:
        """Get overall OpenAI usage statistics for this session"""
        try:
            session_duration = datetime.utcnow() - self.session_start
            hours_running = session_duration.total_seconds() / 3600
            
            return {
                'total_tokens_used': self.total_tokens_used,
                'api_calls_made': self.api_calls_made,
                'session_start': self.session_start.strftime("%Y-%m-%d %H:%M:%S UTC"),
                'session_duration_hours': round(hours_running, 2),
                'average_tokens_per_call': round(self.total_tokens_used / max(self.api_calls_made, 1), 2),
                'tokens_per_hour': round(self.total_tokens_used / max(hours_running, 0.01), 2),
                'model': self.openai_model,
                'max_tokens_per_request': self.max_tokens,
                'temperature': self.temperature,
                'integration_enabled': self.enabled
            }
        except Exception as e:
            logger.error(f"Error getting usage statistics: {e}")
            return {'error': str(e)}
    
    async def close(self):
        """Close the HTTP session"""
        if self.session:
            await self.session.close()
            self.session = None
            logger.debug("Closed OpenAI HTTP session")
