#!/usr/bin/env python3
"""
Discord Bot with OpenAI ChatGPT Integration - Main Entry Point
"""

import sys
import os
import asyncio
import logging

def main():
    """Main function - can run either Discord bot or simple hello world"""
    if len(sys.argv) > 1 and sys.argv[1] == '--discord':
        # Run Discord bot
        from discord_bot import main as discord_main
        discord_main()
    else:
        # Run simple hello world
        print("Hello, World!")
        print("Welcome to your Discord OpenAI ChatGPT integration project!")
        print("\nTo run the Discord bot:")
        print("1. Copy .env.example to .env and fill in your credentials")
        print("2. Run: python main.py --discord")
        print("\nOr use Docker:")
        print("docker-compose up -d")
        print("\nOr use Helm:")
        print("helm install discord-bot ./helm/discord-bot")

if __name__ == "__main__":
    main()
