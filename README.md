# Zig Tree Clone

A lightweight, fast implementation of the popular `tree` command, written in Zig for macOS systems.

Why install tree from homebrew when you can rewrite it from scratch?

## Features

- Display directory structures in a tree-like format
- Custom sorting logic:
    - Hidden files first (when enabled)
    - Uppercase files/directories first
    - Directories before files
    - Alphanumeric sorting
- Command-line flags to customize behavior
- Memory-safe implementation using Zig

## Installation

### Requirements

- Zig language (0.15.2 or later recommended)

### Building from Source

```bash
# Clone the repository
git clone https://github.com/dbrtly/tree.git
cd tree

# Build the executable
zig build

# test the code
zig test tree.zig

# Optional: Move to a directory in your PATH
cp tree /usr/local/bin/
```

## Usage

Basic usage:

```bash
# Show tree structure of current directory
./tree

# Show tree structure of specified directory
./tree /path/to/directory
```

### Command Line Options

| Flag   | Long Form       | Description                                |
| ------ | --------------- | ------------------------------------------ |
| `-a`   | `--all`         | Show hidden files (starting with `.`)      |
| `-L n` | `--max-depth n` | Limit directory recursion to n levels deep |

|

## Examples

Show all files including hidden ones:

```bash
./tree -a
```

Limit directory depth to 2 levels:

```bash
./tree -L 2
```

Combine options:

```bash
./tree -a -L 3 ~/Documents
```

## Output Example

```bash
tree
├── README.md
├── installer.sh
├── tree
├── tree.o
└── tree.zig
```

```bash
$ tree --all

tree
├── .zig-cache
│   └── tmp
├── .gitattributes
├── .gitignore
├── README.md
├── installer.sh
├── tree
├── tree.o
└── tree.zig
```

## Differences from Standard Tree

- Optimized for macOS
- Custom sorting algorithm prioritizing:
    1. Hidden files (when shown)
    2. Uppercase items
    3. Directories
    4. Alphanumeric order

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
