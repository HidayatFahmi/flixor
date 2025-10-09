#!/bin/bash
#
# Create Xcode Project for FlixorMac
# This script creates an Xcode project from the Swift source files
#

set -e

cd "$(dirname "$0")"

echo "🚀 Creating Xcode project for FlixorMac..."

# Check if swift package is available
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift is not installed or not in PATH"
    echo "Please install Xcode from the Mac App Store"
    exit 1
fi

# Create Package.swift if it doesn't exist
if [ ! -f "FlixorMac/Package.swift" ]; then
    echo "📦 Creating Package.swift..."
    cd FlixorMac
    swift package init --type executable --name FlixorMac
    cd ..
fi

# Generate Xcode project from Package.swift
echo "🔨 Generating Xcode project..."
cd FlixorMac
swift package generate-xcodeproj

if [ -d "FlixorMac.xcodeproj" ]; then
    echo "✅ Xcode project created successfully!"
    echo ""
    echo "📂 Project location: apps/macos/FlixorMac/FlixorMac.xcodeproj"
    echo ""
    echo "Next steps:"
    echo "1. Open FlixorMac.xcodeproj in Xcode"
    echo "2. Select the FlixorMac scheme"
    echo "3. Press ⌘R to build and run"
    echo ""
    echo "Opening project in Xcode..."
    open FlixorMac.xcodeproj
else
    echo "❌ Failed to create Xcode project"
    exit 1
fi
