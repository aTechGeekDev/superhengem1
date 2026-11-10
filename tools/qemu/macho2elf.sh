#!/bin/sh
# Mach-O assembler syntax to ELF: C symbols lose their leading underscore, @PAGE/@PAGEOFF become adrp/:lo12:.
sed -E \
 -e 's/([A-Za-z0-9_]+)@PAGEOFF/:lo12:\1/g' \
 -e 's/([A-Za-z0-9_]+)@PAGE/\1/g' \
 -e 's/:lo12:_([A-Za-z])/:lo12:\1/g' \
 -e 's/(adrp[^,]*, )_([A-Za-z])/\1\2/g' \
 -e 's/(\.globl[[:space:]]+)_/\1/g' \
 -e 's/^_([A-Za-z\\])/\1/' \
 -e 's/([[:space:],])_\\name/\1\\name/g' \
 -e 's/^_\\name/\\name/' \
 -e 's/(\bb[l]?[[:space:]]+)_([A-Za-z])/\1\2/g' \
 -e 's/(\bb\.?[a-z]*[[:space:]]+)_([a-z])/\1\2/g' \
 -e '/subsections_via_symbols/d' "$1"
