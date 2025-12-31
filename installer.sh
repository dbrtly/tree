#!/bin/bash

# Installer script for Tree Clone
# This script will install  Zig Tree to ~/.local/bin

set -e  # Exit immediately if a command exits with a non-zero status

echo "Tree Installer"
echo "=========================="

ZIG_VERSION="0.15.2"

# Function to download and install Zig if not found
install_zig() {
    echo "Zig not found. Installing from official binary..."

    # Create temporary directory for Zig download
    ZIG_TEMP=$(mktemp -d)

    # Determine system architecture
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    # Set appropriate URL based on architecture
    if [[ "$ARCH" == "x86_64" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-macos-x86_64-${ZIG_VERSION}.tar.xz"
        elif [[ "$OS" == "linux" ]]; then
            ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
        fi
    elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-macos-aarch64-${ZIG_VERSION}.tar.xz"
        elif [[ "$OS" == "linux" ]]; then
            ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-aarch64-${ZIG_VERSION}.tar.xz"
        fi
    fi

    if [[ -z "$ZIG_URL" ]]; then
        echo "❌ Could not determine appropriate Zig download for your system."
        echo "   Please download and install Zig manually from https://ziglang.org/download/"
        rm -rf "$ZIG_TEMP"
        exit 1
    fi

    echo "Downloading Zig from $ZIG_URL"

    # Download Zig
    if ! curl -L "$ZIG_URL" -o "$ZIG_TEMP/zig.tar.xz"; then
        echo "❌ Failed to download Zig. Please check your internet connection."
        rm -rf "$ZIG_TEMP"
        exit 1
    fi

    # Extract Zig
    ZIG_DIR="${HOME}/.zig-${ZIG_VERSION}"
    mkdir -p "${ZIG_DIR}"
    echo "Extracting Zig to ${ZIG_DIR}"
    tar -xf "$ZIG_TEMP/zig.tar.xz" -C "$ZIG_DIR"

    # Copy Zig binary to ~/.local/bin
    echo "Installing Zig to ~/.local/bin/"
    mkdir -p "$HOME/.local/bin/"
    ln -s "${ZIG_DIR}/zig" "${HOME}/.local/bin/"

    # Add ~/.local/bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "Adding ~/.local/bin to your PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
        if [[ -f "$HOME/.zshrc" ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        fi
        export PATH="$HOME/.local/bin:$PATH"
    fi

    echo "Zig installed to ~/.local/bin/"

    # Clean up
    rm -rf "$ZIG_TEMP"

    # Test if Zig is working
    if ! command -v zig &> /dev/null; then
        echo "❌ Zig installation failed. Please add ~/.local/bin to your PATH and try again."
        exit 1
    fi
}

install_dir() {
    # Ensure ~/.local/bin exists
    mkdir -p "$INSTALL_DIR"

    # Ensure installation directory is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "Warning: $INSTALL_DIR is not in your PATH."
        echo "Adding zig to your PATH configuration files..."

        # Add to common shell configuration files
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"

        # Add to zsh config if it exists
        if [[ -f "$HOME/.zshrc" ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        fi

        echo "   Please restart your terminal or run: export PATH=\"$HOME/.local/bin:\$PATH\""
    fi
}

# Check if Zig is installed
if ! command -v zig &> /dev/null; then
    install_zig
else
    echo "Zig is already installed"
fi

zig build

# Install to ~/.local/bin
INSTALL_DIR="$HOME/.zig-${ZIG_VERSION}"
echo "Installing to $INSTALL_DIR/tree..."

install_dir

# Copy the executable to the installation directory
BUILD_OUTPUT="${PWD}/zig-out/bin/tree"
cp "$BUILD_OUTPUT" "$INSTALL_DIR/tree"
chmod +x "$INSTALL_DIR/tree"

echo "Installation complete"
