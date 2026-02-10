#!/bin/bash

# Script to convert HTML files to markdown
# Usage: ./convert-html-to-markdown.sh <input_folder> <output_folder>

# Check if input and output folders are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <input_folder> <output_folder>"
    echo "Example: $0 ./input ./output"
    exit 1
fi

INPUT_FOLDER="$1"
OUTPUT_FOLDER="$2"

# Check if input folder exists
if [ ! -d "$INPUT_FOLDER" ]; then
    echo "Error: Input folder '$INPUT_FOLDER' does not exist."
    exit 1
fi

# Create output folder if it doesn't exist
mkdir -p "$OUTPUT_FOLDER"

# Count total files processed
total_files=0
success_files=0
error_files=0

echo "Converting HTML files from '$INPUT_FOLDER' to '$OUTPUT_FOLDER'..."
echo "----------------------------------------"

# Loop through all HTML files in the input folder
for file in "$INPUT_FOLDER"/*.html; do
    # Check if the glob matched any files
    if [ ! -f "$file" ]; then
        echo "No HTML files found in '$INPUT_folder'"
        exit 0
    fi

    # Get the filename (without path)
    filename=$(basename -- "$file")
    filename_no_ext="${filename%.*}"

    # Increment counter
    ((total_files++))

    echo "Processing: $filename"

    # Run html2markdown command
    if html2markdown --input "$file" --output "$OUTPUT_FOLDER/" --output-overwrite; then
        echo "✓ Success: $filename"
        ((success_files++))
    else
        echo "✗ Error: $filename"
        ((error_files++))
    fi

    echo "----------------------------------------"
done

echo "----------------------------------------"
echo "Conversion complete!"
echo "Total files: $total_files"
echo "Successful: $success_files"
echo "Errors: $error_files"