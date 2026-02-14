#!/usr/bin/env python3
"""
Patched MLX Server - Disables uvloop to fix OpenAI SDK compatibility
This patches mlx_lm.server to use asyncio loop instead of uvloop
"""
import sys
import os

# Patch 1: Disable uvloop before any imports
os.environ['UVLOOP_DISABLE'] = '1'

# Patch 2: Mock uvloop to prevent it from being used
sys.modules['uvloop'] = None

# Patch 3: Force asyncio as loop implementation
import asyncio
if hasattr(asyncio, 'set_event_loop_policy'):
    asyncio.set_event_loop_policy(asyncio.DefaultEventLoopPolicy())

# Now import and run the server
from mlx_lm import server

if __name__ == '__main__':
    print("🔧 Starting MLX server with uvloop disabled (OpenAI SDK compatibility fix)")
    server.main()
