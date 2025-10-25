#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pillow",
# ]
# ///
"""
Image information script using Pillow.
Demonstrates a script with external dependencies that uv will automatically install.
"""

import sys
from pathlib import Path
from PIL import Image


def main():
    if len(sys.argv) < 2:
        print("Usage: python image_info.py <image_path>")
        print("\nExample: python image_info.py example.jpg")
        sys.exit(1)
    
    image_path = Path(sys.argv[1])
    
    if not image_path.exists():
        print(f"Error: Image file not found: {image_path}")
        sys.exit(1)
    
    try:
        with Image.open(image_path) as img:
            print(f"Image Information for: {image_path.name}")
            print(f"  Format: {img.format}")
            print(f"  Mode: {img.mode}")
            print(f"  Size: {img.size[0]}x{img.size[1]} pixels")
            if hasattr(img, 'info'):
                print(f"  Additional info: {img.info}")
    except Exception as e:
        print(f"Error reading image: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
