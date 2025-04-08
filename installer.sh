#!/bin/bash

# Installer script for Tree Clone
# This script will install the Zig Tree Clone to ~/.local/bin

set -e  # Exit immediately if a command exits with a non-zero status

echo "📂 Tree Clone Installer"
echo "=========================="

VERSION="0.14.0"

# Function to download and install Zig if not found
install_zig() {
    echo "🔍 Zig not found. Installing from official binary..."
    
    # Create temporary directory for Zig download
    ZIG_TEMP=$(mktemp -d)
    
    # Determine system architecture
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    # Set appropriate URL based on architecture
    if [[ "$ARCH" == "x86_64" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            ZIG_URL="https://ziglang.org/download/${VERSION}/zig-macos-x86_64-${VERSION}.tar.xz"
        elif [[ "$OS" == "linux" ]]; then
            ZIG_URL="https://ziglang.org/download/${VERSION}/zig-linux-x86_64-${VERSION}.tar.xz"
        fi
    elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            ZIG_URL="https://ziglang.org/download/${VERSION}/zig-macos-aarch64-${VERSION}.tar.xz"
        elif [[ "$OS" == "linux" ]]; then
            ZIG_URL="https://ziglang.org/download/${VERSION}/zig-linux-aarch64-${VERSION}.tar.xz"
        fi
    fi
    
    if [[ -z "$ZIG_URL" ]]; then
        echo "❌ Could not determine appropriate Zig download for your system."
        echo "   Please download and install Zig manually from https://ziglang.org/download/"
        rm -rf "$ZIG_TEMP"
        exit 1
    fi
    
    echo "📥 Downloading Zig from $ZIG_URL"
    
    # Download Zig
    if ! curl -L "$ZIG_URL" -o "$ZIG_TEMP/zig.tar.xz"; then
        echo "❌ Failed to download Zig. Please check your internet connection."
        rm -rf "$ZIG_TEMP"
        exit 1
    fi
    
    # Extract Zig
    ZIG_DIR="${HOME}/.zig-${VERSION}"
    mkdir -p "${ZIG_DIR}"
    echo "📦 Extracting Zig to ${ZIG_DIR}"
    tar -xf "$ZIG_TEMP/zig.tar.xz" -C "$ZIG_DIR"
    
    # Copy Zig binary to ~/.local/bin
    echo "📦 Installing Zig to ~/.local/bin/"
    mkdir -p "$HOME/.local/bin/"
    ln -s "${ZIG_DIR}/zig" "${HOME}/.local/bin/"
    
    # Add ~/.local/bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "⚠️ Adding ~/.local/bin to your PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
        if [[ -f "$HOME/.zshrc" ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        fi
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    echo "✅ Zig installed to ~/.local/bin/"
    
    # Clean up
    rm -rf "$ZIG_TEMP"
    
    # Test if Zig is working
    if ! command -v zig &> /dev/null; then
        echo "❌ Zig installation failed. Please add ~/.local/bin to your PATH and try again."
        exit 1
    fi
}

build_tree() {
    # Check if Zig is installed
    if ! command -v zig &> /dev/null; then
        install_zig
    else
        echo "✅ Zig is already installed"
    fi

    # Ensure ~/.local/bin exists
    mkdir -p "$HOME/.local/bin"

    # Create a temporary directory for building
    TEMP_DIR=$(mktemp -d)
    echo "📁 Created temporary directory: $TEMP_DIR"

    # Check if the current script directory contains tree.zig
    SOURCE_FILE=""
    if [ -f "./tree.zig" ]; then
        SOURCE_FILE="./tree.zig"
        echo "✅ Found tree.zig in current directory"
    else
        # If tree.zig is not in the current directory, download it
        echo "🔍 tree.zig not found in current directory, downloading..."
        
        # URL to the raw file (adjust accordingly to your repository)
        SOURCE_URL="https://raw.githubusercontent.com/yourusername/zig-tree/main/tree.zig"
        
        # Download tree.zig to the temporary directory
        if ! curl -s "$SOURCE_URL" -o "$TEMP_DIR/tree.zig"; then
            echo "❌ Failed to download tree.zig. Please check your internet connection."
            echo "   Or manually place tree.zig in the current directory and run this script again."
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        SOURCE_FILE="$TEMP_DIR/tree.zig"
        echo "✅ Downloaded tree.zig"
    fi

    # Build the executable
    echo "🔨 Building tree..."
    (cd "$TEMP_DIR" && zig build-exe "$SOURCE_FILE" -O ReleaseFast)

    # Get the build output file
    if [ -f "$TEMP_DIR/tree" ]; then
        BUILD_OUTPUT="$TEMP_DIR/tree"
    elif [ -f "$TEMP_DIR/tree.exe" ]; then
        BUILD_OUTPUT="$TEMP_DIR/tree.exe"
    else
        echo "❌ Could not find the compiled binary."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "✅ Build successful"
}


# Install to ~/.local/bin
INSTALL_DIR="$HOME/.zig-${VERSION}"
echo "📦 Installing to $INSTALL_DIR/tree..."

# Ensure ~/.local/bin exists
mkdir -p "$INSTALL_DIR"

# Copy the executable to the installation directory
cp "$BUILD_OUTPUT" "$INSTALL_DIR/tree"
chmod +x "$INSTALL_DIR/tree"

echo "✅ Installation complete"

# Clean up
rm -rf "$TEMP_DIR"
echo "🧹 Cleaned up temporary files"

# Check if installation directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠️ Warning: $INSTALL_DIR is not in your PATH."
    echo "   Adding it to your PATH configuration files..."
    
    # Add to common shell configuration files
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
    
    # Add to zsh config if it exists
    if [[ -f "$HOME/.zshrc" ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    fi
    
    echo "   Please restart your terminal or run: export PATH=\"$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "🎉 Zig Tree Clone has been successfully installed!"
echo "   You can now run it by typing 'tree' in your terminal."
echo ""
echo "📚 Usage examples:"
echo "   tree                  # List files in current directory"
echo "   tree -a               # Show hidden files"
echo "   tree -L 2             # Limit depth to 2 levels"
echo "   tree /path/to/dir     # List files in specified directory"
