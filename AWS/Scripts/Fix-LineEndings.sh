#!/bin/bash
# Fix line endings for PowerShell scripts
# Converts Unix (LF) line endings to Windows (CRLF) line endings
# Removes UTF-8 BOM if present (can cause PowerShell issues)
# Ensures proper encoding and trailing line handling

echo "===== Fixing Line Endings for PowerShell Scripts ====="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Count files
total=0
fixed=0
bom_removed=0

# Process all .ps1 files
for file in "$SCRIPT_DIR"/*.ps1; do
    if [ -f "$file" ]; then
        total=$((total + 1))
        filename=$(basename "$file")

        needs_fix=false

        # Check for UTF-8 BOM (EF BB BF)
        if hexdump -C "$file" | head -1 | grep -q "ef bb bf"; then
            echo "Removing UTF-8 BOM: $filename"
            # Remove BOM
            tail -c +4 "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            bom_removed=$((bom_removed + 1))
            needs_fix=true
        fi

        # Check if file has Unix line endings or needs normalization
        if ! file "$file" | grep -q "CRLF"; then
            needs_fix=true
        fi

        if [ "$needs_fix" = true ]; then
            echo "Converting: $filename"

            # Convert to Windows line endings using perl (works on macOS/Linux)
            # This handles LF, CR, and CRLF uniformly
            perl -pi -e 's/\r\n|\r|\n/\r\n/g' "$file"

            # Ensure file ends with exactly one CRLF (no extra blank lines)
            perl -pi -e 'chomp if eof' "$file"
            echo -ne '\r\n' >> "$file"

            fixed=$((fixed + 1))
        else
            echo "✓ Already correct: $filename"
        fi
    fi
done

echo ""
echo "===== Line Ending Conversion Complete! ====="
echo "Total PowerShell files: $total"
echo "Files converted: $fixed"
echo "UTF-8 BOM removed from: $bom_removed"
echo ""
echo "All .ps1 files now have:"
echo "  - Windows (CRLF) line endings"
echo "  - No UTF-8 BOM"
echo "  - Proper trailing line"
echo ""
echo "These files should work correctly in PowerShell on Windows."
echo ""

