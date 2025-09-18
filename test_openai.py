#!/usr/bin/env python3
"""
Test script for OpenAI ChatGPT integration
"""

import asyncio
import os
import logging
import json
from dotenv import load_dotenv
from openai_integration import OpenAIIntegration
from message_filter import MessageFilter

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

class MockMessage:
    """Mock Discord message for testing"""
    def __init__(self, content, author_name="TestUser", channel_name="test-channel"):
        self.content = content
        self.author = type('Author', (), {
            'name': author_name,
            'display_name': author_name,
            'id': 123456789,
            'bot': False,
            'guild_permissions': type('Permissions', (), {
                'manage_messages': False,
                'administrator': False
            })()
        })()
        self.channel = type('Channel', (), {
            'name': channel_name,
            'id': 987654321,
            'type': 'text'
        })()
        self.guild = type('Guild', (), {
            'name': 'Test Server',
            'id': 111222333
        })()
        self.id = 999888777
        self.created_at = "2025-09-07T12:00:00Z"
        self.mentions = []
        self.attachments = []
        self.embeds = []

async def test_openai_integration():
    """Test the OpenAI integration"""
    print("🧪 OpenAI Integration Test Suite")
    print("=" * 50)
    
    # Test message filter first
    print("\n🔍 Testing Message Filter...")
    message_filter = MessageFilter()
    
    test_messages = [
        "Hello, this is a normal test message",
        "This message has LOTS OF CAPS AND MIGHT BE SPAM",
        "spam spam spam inappropriate content here",
        "A nice positive message with good vibes!",
        "```python\nprint('This has code in it')\n```",
        "Check out this link: https://example.com"
    ]
    
    for msg_content in test_messages:
        mock_message = MockMessage(msg_content)
        filter_result = await message_filter.analyze_message(mock_message)
        print(f"✅ Message: '{msg_content[:30]}{'...' if len(msg_content) > 30 else ''}'")
        print(f"   Should Process: {filter_result['should_process']}")
        print(f"   User Authorized: {filter_result['user_authorized']}")
        print(f"   Content Safe: {filter_result['content_safe']}")
        print(f"   Sentiment: {filter_result['analysis'].get('sentiment', 'unknown')}")
        print()
    
    # Test OpenAI integration
    print("\n🤖 Testing OpenAI Integration...")
    openai_integration = OpenAIIntegration()
    
    # Print environment variables (masked)
    print("Environment Variables:")
    print(f"  OPENAI_API_KEY: {'*' * 20 if openai_integration.openai_api_key and openai_integration.openai_api_key != 'your-openai-api-key-here' else 'NOT SET'}")
    print(f"  OPENAI_MODEL: {openai_integration.openai_model}")
    print(f"  OPENAI_MAX_TOKENS: {openai_integration.max_tokens}")
    print(f"  OPENAI_TEMPERATURE: {openai_integration.temperature}")
    print(f"  OPENAI_INTEGRATION_ENABLED: {openai_integration.enabled}")
    print()
    
    # Test with a sample message that passes filter
    test_message = MockMessage("Hello ChatGPT, can you help me with Python programming?")
    filter_result = {
        'should_process': True,
        'user_authorized': True,
        'content_safe': True,
        'rate_limited': False,
        'analysis': {
            'word_count': 10,
            'sentiment': 'neutral'
        }
    }
    
    print(f"Filter Result: {filter_result['should_process']}")
    
    if filter_result['should_process']:
        print("✅ Message passed filter, testing OpenAI integration...")
        
        # Test message preparation
        chat_messages = await openai_integration._prepare_chat_messages(test_message, filter_result)
        print(f"✅ Prepared chat messages: {len(chat_messages)} messages")
        for i, msg in enumerate(chat_messages):
            print(f"   Message {i+1}: {msg['role']} - {msg['content'][:50]}...")
        
        # Test API call (only if API key is configured)
        if openai_integration.openai_api_key and openai_integration.openai_api_key != "your-openai-api-key-here":
            print("\n🚀 Testing actual OpenAI API call...")
            try:
                response = await openai_integration._send_to_openai(chat_messages)
                if response:
                    print("✅ OpenAI API call successful!")
                    print(f"   Response: {json.dumps(response, indent=2)}")
                else:
                    print("❌ No response from OpenAI API")
            except Exception as e:
                print(f"❌ OpenAI API call failed: {e}")
        else:
            print("⚠️ OpenAI API key not configured - skipping actual API test")
    else:
        print("❌ Message did not pass filter")
    
    # Clean up
    await openai_integration.close()
    
    print("\n✅ Test completed!")

async def interactive_test():
    """Interactive test mode"""
    print("\n💬 Interactive Test Mode")
    print("Type messages to test (type 'quit' to exit):")
    
    openai_integration = OpenAIIntegration()
    message_filter = MessageFilter()
    
    while True:
        try:
            user_input = input("\nEnter test message: ").strip()
            if user_input.lower() in ['quit', 'exit', 'q']:
                break
            
            if not user_input:
                continue
            
            # Create mock message
            mock_message = MockMessage(user_input)
            
            # Filter the message
            filter_result = await message_filter.analyze_message(mock_message)
            print(f"Filter Result: {filter_result['should_process']}")
            
            if filter_result['should_process']:
                # Test OpenAI integration
                await openai_integration.relay_message(mock_message, filter_result)
            else:
                print("Message was filtered out")
                
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
    
    await openai_integration.close()
    print("Goodbye!")

async def main():
    """Main test function"""
    await test_openai_integration()
    
    # Ask if user wants interactive mode
    try:
        interactive = input("\nWould you like to run interactive test mode? (y/n): ").strip().lower()
        if interactive in ['y', 'yes']:
            await interactive_test()
    except KeyboardInterrupt:
        print("\nExiting...")

if __name__ == "__main__":
    asyncio.run(main())
