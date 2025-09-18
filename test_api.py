#!/usr/bin/env python3
"""
Simple Copilot API Test - Tests just the HTTP calls
"""

import asyncio
import aiohttp
import json
import os
from dotenv import load_dotenv

load_dotenv()

async def test_copilot_endpoint():
    """Test the Copilot endpoint directly"""
    
    endpoint = os.getenv('COPILOT_365_ENDPOINT')
    api_key = os.getenv('COPILOT_365_API_KEY')
    
    print(f"🔗 Testing endpoint: {endpoint}")
    
    if not endpoint:
        print("❌ No COPILOT_365_ENDPOINT configured")
        return
    
    # Test data
    test_payload = {
        "message": "Hello, this is a test message",
        "user": "test_user",
        "timestamp": "2025-09-07T12:00:00Z"
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
    }
    
    if api_key and api_key != "using_azure_ad_so_it_blank":
        headers['Authorization'] = f'Bearer {api_key}'
    
    async with aiohttp.ClientSession() as session:
        try:
            # Test GET request first
            print("\n📥 Testing GET request...")
            async with session.get(endpoint, headers=headers) as response:
                print(f"GET Status: {response.status}")
                if response.status == 200:
                    text = await response.text()
                    print(f"GET Response: {text[:200]}...")
                
        except Exception as e:
            print(f"GET Error: {e}")
        
        try:
            # Test POST request
            print("\n📤 Testing POST request...")
            async with session.post(endpoint, headers=headers, json=test_payload) as response:
                print(f"POST Status: {response.status}")
                text = await response.text()
                print(f"POST Response: {text[:200]}...")
                
                if response.status == 200:
                    try:
                        data = await response.json()
                        print(f"JSON Response: {json.dumps(data, indent=2)}")
                    except:
                        print("Response is not valid JSON")
                        
        except Exception as e:
            print(f"POST Error: {e}")

async def test_microsoft_graph():
    """Test Microsoft Graph API endpoints"""
    
    print("\n🔍 Testing Microsoft Graph API...")
    
    # Common Graph API endpoints to test
    endpoints = [
        "https://graph.microsoft.com/v1.0",
        "https://graph.microsoft.com/v1.0/me",
        "https://graph.microsoft.com/v1.0/users"
    ]
    
    async with aiohttp.ClientSession() as session:
        for endpoint in endpoints:
            try:
                print(f"\nTesting: {endpoint}")
                async with session.get(endpoint) as response:
                    print(f"Status: {response.status}")
                    if response.status != 200:
                        text = await response.text()
                        print(f"Response: {text[:100]}...")
                        
            except Exception as e:
                print(f"Error: {e}")

if __name__ == "__main__":
    print("🧪 Simple Copilot API Test")
    print("=" * 40)
    
    asyncio.run(test_copilot_endpoint())
    asyncio.run(test_microsoft_graph())
