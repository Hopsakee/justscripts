# justscripts

A repository containing self-contained Python scripts that can be run using `uv` with inline metadata for dependency management. Scripts are organized and easily executable through a `justfile`.

## Overview

This repository contains Python scripts that use [uv](https://docs.astral.sh/uv/)'s inline script metadata feature (PEP 723). Each script declares its own dependencies directly in the file, making them completely self-contained and easy to run without manual dependency management.

## Prerequisites

- **uv**: Install from [https://docs.astral.sh/uv/](https://docs.astral.sh/uv/)
  ```bash
  # On macOS/Linux
  curl -LsSf https://astral.sh/uv/install.sh | sh
  
  # On Windows
  powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
  ```

- **just** (optional but recommended): Install from [https://just.systems/](https://just.systems/)
  ```bash
  # On macOS
  brew install just
  
  # On Linux
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/bin
  
  # On Windows
  choco install just
  ```

## Usage

### Using uv directly

All scripts can be run directly with `uv`:

```bash
# Run a simple script
uv run scripts/hello_world.py

# Run a script with dependencies
uv run scripts/image_info.py path/to/image.jpg
```

The first time you run a script, `uv` will automatically:
1. Create an isolated environment
2. Install the required dependencies
3. Execute the script

### Using the justfile

For convenience, you can use the included `justfile`:

```bash
# Show available commands
just

# Run the hello world script
just hello

# Run the image info script
just image-info path/to/image.jpg

# List all available scripts
just list-scripts

# Run any script by name (with optional arguments)
just run hello_world
just run image_info path/to/image.jpg
```

### Using from your home directory or project

You can copy the `justfile` to your WSL home directory or Python project root, then add recipes that reference scripts from this repository:

```bash
# Copy justfile to your home directory
cp justfile ~/justfile

# Edit ~/justfile and add custom recipes
# For example:
# image-info IMAGE_PATH:
#     uv run /path/to/justscripts/scripts/image_info.py {{IMAGE_PATH}}
```

## Adding New Scripts

To add a new script to this repository:

1. Create a new Python file in the `scripts/` directory
2. Add the uv shebang and inline metadata at the top:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "requests",
#   "beautifulsoup4",
# ]
# ///
"""
Your script description here.
"""

def main():
    # Your code here
    pass

if __name__ == "__main__":
    main()
```

3. Make the script executable:
```bash
chmod +x scripts/your_script.py
```

4. (Optional) Add a recipe to the `justfile`:
```bash
# Run your custom script
your-script:
    uv run scripts/your_script.py
```

## Available Scripts

- **hello_world.py**: Simple hello world script with no dependencies
- **image_info.py**: Display information about an image file (uses Pillow)
- **github_repo_info.py**: Fetch and display GitHub repository information (uses requests)

## Script Template

Here's a template for creating new scripts:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   # Add your dependencies here
# ]
# ///
"""
Script description.
"""

import sys


def main():
    # Your code here
    print("Script running!")


if __name__ == "__main__":
    main()
```

## How It Works

The inline script metadata is a standardized format (PEP 723) that allows scripts to declare their dependencies directly in the file. The metadata block looks like this:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "package-name>=1.0.0",
# ]
# ///
```

When you run the script with `uv run`, it:
1. Parses the inline metadata
2. Creates an isolated virtual environment
3. Installs the specified dependencies
4. Runs the script in that environment

This approach keeps each script self-contained and eliminates the need for separate `requirements.txt` files or manual environment management.

## License

See [LICENSE](LICENSE) file for details.
