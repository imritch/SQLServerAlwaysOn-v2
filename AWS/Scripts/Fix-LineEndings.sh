#!/bin/bash
# Fix line endings for PowerShell scripts
# Converts Unix (LF) line endings to Windows (CRLF) line endings
# This fixes PowerShell parsing errors on Windows

echo "===== Fixing Line Endings for PowerShell Scripts ====="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Count files
total=0
fixed=0

# Process all .ps1 files
for file in "$SCRIPT_DIR"/*.ps1; do
    if [ -f "$file" ]; then
        total=$((total + 1))
        filename=$(basename "$file")
        
        # Check if file has Unix line endings
        if file "$file" | grep -q "ASCII text$\|UTF-8.*text$" && ! file "$file" | grep -q "CRLF"; then
            echo "Converting: $filename"
            
            # Convert to Windows line endings using perl (works on macOS/Linux)
            perl -pi -e 's/\r?\n/\r\n/g' "$file"
            
            # Remove any trailing blank lines and ensure file ends with CRLF
            perl -pi -e 's/\s+$/\r\n/ if eof' "$file"
            
            fixed=$((fixed + 1))
        else
            echo "Skipping: $filename (already has CRLF)"
        fi
    fi
done

echo ""
echo "===== Line Ending Conversion Complete! ====="
echo "Total PowerShell files: $total"
echo "Files converted: $fixed"
echo ""
echo "All .ps1 files now have Windows (CRLF) line endings."
echo "They should work correctly in PowerShell on Windows."
echo ""

