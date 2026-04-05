import discord
import os
import sys
import argparse
import asyncio
from dotenv import load_dotenv

load_dotenv()
DISCORD_TOKEN = os.getenv("DISCORD_TOKEN")


async def send_message(channel_id, title, message, color=discord.Color.blue()):
    """Send a single embed message to a Discord channel and exit."""
    intents = discord.Intents.default()
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        try:
            channel = client.get_channel(channel_id)
            if channel is None:
                channel = await client.fetch_channel(channel_id)

            embed = discord.Embed(
                title=title,
                description=message,
                color=color,
            )
            embed.set_footer(text="Svarog Krysa PR 🐀")

            await channel.send(embed=embed)
            print(f"Message sent to channel {channel_id}")
        except Exception as e:
            print(f"Error sending message: {e}")
            sys.exit(1)
        finally:
            await client.close()

    await client.start(DISCORD_TOKEN)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Svarog Krysa PR 🐀 — Send PR review summaries to Discord")
    parser.add_argument("--channel", type=int, required=True, help="Discord channel ID")
    parser.add_argument("--title", type=str, default="PR Review 🐀", help="Embed title")
    parser.add_argument("--message", type=str, required=True, help="Message body (supports markdown)")
    args = parser.parse_args()

    if not DISCORD_TOKEN:
        print("DISCORD_TOKEN is required in .env")
        sys.exit(1)

    asyncio.run(send_message(args.channel, args.title, args.message))
