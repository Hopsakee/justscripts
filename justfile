# justfile for running self-contained Python scripts with uv
# See https://just.systems/ for more information about justfiles

# Default recipe - shows available commands
default:
    @just --list

# Run the hello world script
hello:
    uv run scripts/hello_world.py

# Run the image info script with an image path
# Usage: just image-info <path_to_image>
image-info IMAGE_PATH:
    uv run scripts/image_info.py {{IMAGE_PATH}}

# Get GitHub repository information
# Usage: just github-info <owner/repo>
github-info REPO:
    uv run scripts/github_repo_info.py {{REPO}}

# List all available scripts
list-scripts:
    @echo "Available scripts:"
    @ls -1 scripts/*.py | sed 's|scripts/||' | sed 's|\.py$||'

# Run any script by name (without .py extension)
# Usage: just run <script_name> [args...]
run SCRIPT *ARGS:
    uv run scripts/{{SCRIPT}}.py {{ARGS}}

# Resize PNG images by a given factor
resize-images factor *files:
    cd {{invocation_directory_native()}} && uv run '{{home_dir()}}/justscripts/scripts/resize_images.py' {{factor}} {{files}}

