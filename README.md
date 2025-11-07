# justscripts

A repository containing self-contained Python scripts that can be run using `uv` with inline metadata for dependency management. Scripts are organized and easily executable through a `justfile`.

## Overview

This repository contains Python scripts that use [uv](https://docs.astral.sh/uv/)'s inline script metadata feature (PEP 723). Each script declares its own dependencies directly in the file, making them completely self-contained and easy to run without manual dependency management. The scripts can be run using `uv run` or `just` through a `justfile`.

## Prerequisites

- **uv**: Install from [https://docs.astral.sh/uv/](https://docs.astral.sh/uv/)
  ```bash
  # On macOS/Linux
  curl -LsSf https://astral.sh/uv/install.sh | sh
  
  # On Windows
  powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
  ```

- **just** (optional but recommended): Install from [https://just.systems/](https://just.systems/)
  There are multiple ways to install `just`. See [Just Programmers Manual - Introduction](https://just.systems/man/en/packages.html).

  For example:
  ```bash
  # Cross platform macOS
  npm install -g rust-just
  ```

## Installation

Clone the repository to your home directory.
_(it is possible to clone to any directory, but this is the recommended location because the provided `justfile` expect the repository to be in your home directory)_

```bash
cd ~
git clone git@github.com:Hopsakee/justscripts.git
# or
git clone https://github.com/Hopsakee/justscripts.git
```

Then copy the `justfile` to your home directory:
```bash
cd ~/justscripts
cp justfile ~
```

## Usage

### Using uv directly

All scripts can be run directly with `uv`:

```bash
# Run a simple script
uv run ~/justscripts/scripts/hello_world.py

# Run a script with dependencies
uv run ~/justscripts/scripts/image_info.py path/to/image.jpg
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

`just` runs recipes from the directory that contains the `justfile` (the working directory). If you invoke `just` from a subdirectory, it still executes recipes from the `justfile`'s directory. See: https://just.systems/man/en/working-directory.html

- **Where paths are resolved**
  - Relative paths in recipes are resolved relative to the `justfile`'s directory.
  - If you copy the `justfile` elsewhere, you must first update its recipe paths to point to the scripts in this repo (use absolute paths or `{{home_dir()}}`). Running commands before editing paths will fail.

- **Run from this repository**
  - `just image-info path/to/image.jpg`
  - Recipe paths like `scripts/image_info.py` are relative to the repo root, so `./scripts/...` works when the `justfile` lives here.

  - Copy the `justfile`, then edit it to reference scripts with `{{home_dir()}}` (preferred) or absolute paths:
  ```bash
  cp justfile ~/justfile
  ```
  Edit `~/justfile` and add/update recipes, e.g.:
  ```just
  image-info IMAGE_PATH:
    uv run {{home_dir()}}/justscripts/scripts/image_info.py {{IMAGE_PATH}}
  ```
  Usage (from anywhere):
  ```bash
  just image-info ~/Pictures/photo.jpg
  ```

- **Use in a specific project**
  - Place a `justfile` in your project root. Since the working directory is the project root, reference this repo with `{{home_dir()}}` or absolute paths:
  ```just
  # project/justfile
  image-info IMAGE_PATH:
    uv run {{home_dir()}}/justscripts/scripts/image_info.py {{IMAGE_PATH}}
  hello:
    uv run {{home_dir()}}/justscripts/scripts/hello_world.py
  ```
  Then run inside your project:
  ```bash
  just image-info data/img.jpg
  just hello
  ```

- **Tip: keep things portable**
  - Prefer `{{home_dir()}}/justscripts/scripts/...` when your `justfile` is not inside this repo.
  - If you want to stay relative, keep the `justfile` in this repo and run `just` from anywhere under it; `just` will execute from the repo root.
## Adding New Scripts

To add a new script to this repository:

1. Create a new Python file in the `scripts/` directory
2. Add the uv shebang and inline metadata at the top of the file. You can use the [Script Template](#script-template) as a reference.
3. Make the script executable:

```bash
chmod +x ~/justscripts/scripts/your_script.py
```

4. (Optional) Add a recipe to the `justfile`:

```bash
# Run your custom script
your-script:
    uv run ~/justscripts/scripts/your_script.py
```

## Script Template

Here's a template for creating new scripts:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   # Add your dependencies here
#   "beautifulsoup4",
# ]
# ///
"""
Script description.
"""

from bs4 import BeautifulSoup

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
