# Contributing to justscripts

Thank you for your interest in contributing to justscripts! This guide will help you add new scripts to the repository.

## Adding a New Script

### Python Scripts

Create a new Python file in the `scripts/` directory with the following structure:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "your-package>=1.0.0",
#   "another-package",
# ]
# ///
"""
Brief description of what your script does.
"""

import sys
# Your imports here


def main():
    # Your code here
    pass


if __name__ == "__main__":
    main()
```

### Bash Scripts

Create a new bash file in the `scripts/` directory with the following structure:

```bash
#!/usr/bin/env bash
# Brief description of what your script does

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: script_name <argument>"
    exit 1
fi

# Your code here
```

**Bash-specific guidelines:**

- External dependencies (e.g., `pandoc`, `ffmpeg`) must be installed separately
- Store configuration files (YAML, etc.) alongside the script
- Use `SCRIPT_DIR="$(dirname "$0")"` to reference config files relative to the script location

## General Guidelines

- **Shebang**: Always start with `#!/usr/bin/env -S uv run`
- **Documentation**: Add a docstring explaining what the script does
- **Error Handling**: Handle errors gracefully and provide helpful error messages
- **Usage Info**: If the script takes arguments, print usage information when run incorrectly
- **Exit Codes**: Use appropriate exit codes (0 for success, non-zero for errors)

## Make It Executable

**bash**

```bash
chmod +x scripts/your_script.sh
```

or

**python**

```bash
chmod +x scripts/your_script.py
```

## (Optional) Add a Justfile Recipe

If your script would benefit from a dedicated recipe, add it to the `justfile`:

**bash**

```just
# Description of what the recipe does
recipe-name ARG:
    {{home_dir()}}/justscripts/scripts/your_script.sh "{{ARG}}"
```

**python**

```just
# Description of what the recipe does
# Usage: just recipe-name <args>
recipe-name ARG:
    uv run {{home_dir()}}/justscripts/scripts/your_script.py "{{ARG}}"
```

_Note: Always quote `"{{ARG}}"` to handle paths with spaces._


## Update Documentation

Add your script to the "Available Scripts" section in `README.md`:

```markdown
- **your_script.py**: Brief description of what it does (list key dependencies)
```


## Submit a Pull Request

1. Fork the repository
2. Create a new branch for your script
3. Commit your changes
4. Push to your fork
5. Open a pull request

## Script Ideas

Here are some ideas for useful scripts:

- File manipulation utilities
- Data processing scripts
- API interaction tools
- System administration helpers
- Development workflow automation
- Text processing utilities
- Media file converters
- Web scraping tools
- Data visualization scripts
- Configuration generators

## Best Practices

1. **Keep it simple**: Each script should do one thing well
2. **Self-contained**: All dependencies should be in the script metadata
3. **Clear output**: Provide informative output and error messages
4. **Help text**: Include usage information for scripts with arguments
5. **Cross-platform**: Consider compatibility across different operating systems
6. **Security**: Don't include sensitive data or credentials in scripts
7. **Performance**: Optimize for reasonable performance but prioritize clarity

## Questions?

If you have questions or need help, please open an issue on GitHub.
