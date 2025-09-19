import os
import aiohttp
import logging
import base64
import io

OPENAI_IMAGE_ENDPOINT = "https://api.openai.com/v1/images/generations"
OPENAI_IMAGE_MODEL = "gpt-image-1"
ALLOWED_QUALITIES = {"low", "medium", "high"}
ALLOWED_SIZES = {"1024x1024", "1536x1024", "1024x1536"}
MAX_PROMPT_LENGTH = 32000

logger = logging.getLogger("openai_image")

async def generate_image(prompt, quality="low", size="1024x1024", moderation="auto", username=None):
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set in environment variables")

    # Log the request
    logger.info(f"Image generation request - User: {username}, Prompt: {prompt}, Quality: {quality}, Size: {size}")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": OPENAI_IMAGE_MODEL,
        "prompt": prompt,
        "quality": quality,
        "size": size,
        "moderation": moderation
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(OPENAI_IMAGE_ENDPOINT, headers=headers, json=payload) as resp:
            if resp.status != 200:
                text = await resp.text()
                logger.error(f"OpenAI image API error for user {username}: {resp.status} - {text}")
                raise RuntimeError(f"OpenAI image API error: {resp.status} - {text}")
            
            response = await resp.json()
            
            # Handle base64 JSON response
            data_list = response.get("data", [])
            if not data_list:
                logger.error(f"No data in OpenAI response for user {username}. Full response: {response}")
                return response
            
            b64_json = data_list[0].get("b64_json")
            if not b64_json:
                logger.error(f"No b64_json in OpenAI response for user {username}. Full response: {response}")
                return response
            
            # Decode base64 image data
            try:
                image_data = base64.b64decode(b64_json)
                logger.info(f"Image generation success - User: {username}, Image size: {len(image_data)} bytes")
                
                # Add the decoded image data to the response for easier access
                response["image_data"] = image_data
                
            except Exception as decode_error:
                logger.error(f"Failed to decode base64 image for user {username}: {decode_error}")
            
            return response