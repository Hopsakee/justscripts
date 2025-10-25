#!/usr/bin/env -S uv run
# /// script
# dependencies = [
#   "pillow",
# ]
# ///
import sys
from pathlib import Path
from PIL import Image
import math

def resize_image(image_path, factor):
    """Resize image by reducing dimensions by sqrt(factor)"""
    img = Image.open(image_path)
    
    # Calculate new dimensions
    scale = 1 / math.sqrt(factor)
    new_width = int(img.width * scale)
    new_height = int(img.height * scale)
    
    # Resize image
    resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Create output path with _small suffix
    path = Path(image_path)
    output_path = path.parent / f"{path.stem}_small{path.suffix}"
    
    # Save with optimization
    resized.save(output_path, optimize=True)
    print(f"✓ {path.name} → {output_path.name} ({img.size} → {resized.size})")

def main():
    if len(sys.argv) < 3:
        print("Usage: resize_images.py <factor> <image1> [image2] ...")
        sys.exit(1)
    
    factor = float(sys.argv[1])
    image_paths = sys.argv[2:]
    
    for path in image_paths:
        try:
            resize_image(path, factor)
        except Exception as e:
            print(f"✗ Error processing {path}: {e}")

if __name__ == "__main__":
    main()
