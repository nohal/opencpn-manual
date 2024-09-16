#!/usr/bin/env bash

# Copyright (c) 2024 Pavel Kalian

# TODO:
#  - Sort the TOC in "correct" order, probably best achievable by numbering the chapters, but the wiki does it based on the "indexmenu" stuff, which is a total mess to use at this level...
#  - Fix the links to "Advanced Manual" to point to either the online wiki or some local place
#  - Fix the missing images
#  - Do something about the main index.html
#  - Handle more of the odities caused by errors in the wiki and imperfect conversion

if [ $# -ne 3 ]; then
	echo "Processes the DokuWiki mess and creates an AsciiDoc site usable in Antora"
	echo "Usage $0 <manual subdirectory to convert> <target directory> <media_path>"
	exit 1
fi

manual=$1
target=$2
media=$3

module_path="modules/ROOT"

if [ ! -d "${manual}" ]; then
	echo "Directory ${manual} does not exist."
	exit 1
fi

rm -rf "${target}"
mkdir -p "${target}/${module_path}/pages"

# Generate the Antora configuration
cat << EOF > "${target}/antora.yml"
name: opencpn
title: OpenCPN Manual
version: ~
nav:
- ${module_path}/nav.adoc
EOF

# Generate the site configuration
cat << EOF > "${target}/site.yml"
site:
  title: OpenCPN Manual
  url:  https://opencpn.org
  start_page: ${manual}.adoc

content:
  sources:
  - url: .
    branches: [HEAD]

ui:
  bundle:
    url: https://gitlab.com/leamas/antora-ui-default/-/raw/master/latest/ui-bundle.zip
    snapshot: true

output:
  dir: ./docs
  clean: true

asciidoc:
  attributes:
    copyright: 2024 OpenCPN Contributors
    license: CC BY-SA 4.0
    license-link: https://creativecommons.org/licenses/by-sa/4.0/
EOF

# Title page of the manual

pandoc -f dokuwiki -t asciidoc "${manual}.txt" > "${target}/${module_path}/pages/${manual}.adoc"
title="$(grep "^=" "${target}/${module_path}/pages/${manual}.adoc" | head -n1 | sed "s/==* *//g")"
echo ".${title}" > "${target}/${module_path}/nav.adoc"

sed -i '/image:.\?indexmenu/d' "${target}/${module_path}/pages/${manual}.adoc"


# Iterate over the content tree

for file in $(find ${manual} -name "*.txt"); do
	echo "${file}"
	# Skip files we do not care about
	if [[ $file == *blank.txt ]]; then
		echo "Skipped.."
		continue
	fi
	if [[ $file == *toc.txt ]]; then
		echo "Skipped.."
		continue
	fi
	# Convert the page to AsciiDoc
	char="/"
	tree_depth=$(awk -F"${char}" '{print NF-1}' <<< "${file}")
	target_subdir=$(echo "${file}" | rev | cut -d'/' -f 2- | rev)
	mkdir -p "${target}/${module_path}/pages/${target_subdir}"
	target_file="$(echo "${file}" | sed "s/\.txt/\.adoc/g")"
	pandoc -f dokuwiki -t asciidoc "${file}" > "${target}/${module_path}/pages/${target_file}"
	# Remove the Dokuwiki page index "image"
	sed -i '/image:.\?indexmenu/d' "${target}/${module_path}/pages/${target_file}"
	# Add page to the table of contents
	tree_depth=$(awk -F"${char}" '{print NF-1}' <<< "${file}")
	title="$(grep "^=" "${target}/${module_path}/pages/${target_file}" | head -n1 | sed "s/==* *//g")"
	up_path=""
	for i in $(seq $tree_depth); do
		echo -n "*" >> "${target}/${module_path}/nav.adoc"
		if [ -z "${up_path=}" ]; then
			up_path="."
		else
			up_path="${up_path}\\/.."
		fi
        done
	echo " xref:${target_file}[${title}]" >> "${target}/${module_path}/nav.adoc"
	# Fix links
	# 1: Relative paths
	sed -i "s/link:.*${manual}\//link:${up_path}\//g" "${target}/${module_path}/pages/${target_file}"
	# 2: Dokuwiki internal links are converted to `link` in AsciiDoc, which means Antora will not make them point to `*.html` and we need to do it ourselves
	sed -i -E "s/(link:[a-z_\/\.-]*)(#.*)?/\1.html\2/g" "${target}/${module_path}/pages/${target_file}"
	# 3: Antora generates anchors prepended with underscore, Dokuwiki does not, so the links do not work correctly. Try to fix it.
	sed -i -E "s/(link:[a-z_\/\.-]*)#(.*)/\1#_\2/g" "${target}/${module_path}/pages/${target_file}"
	# Pull in the required images
	mkdir -p "${target}/${module_path}/images"
	images="$(grep "image:" "${target}/${module_path}/pages/${target_file}" | sed "s/.*image:\(.*\)\[.*\]\?/\1/g" | grep -v "indexmenu")"
	for img in $images; do
		echo "Processing image ${img}..."
		if [ -f ${media}/${img} ]; then
			image_path="$(echo "${img}" | rev | cut -d'/' -f2- | rev)"
			image_name="$(echo "${img}" | rev | cut -d'/' -f1 | rev)"
			target_path="${target}/${module_path}/images/${image_path}"
			mkdir -p "${target_path}"
			cp "${media}/${img}" "${target_path}"
			mime_type=$(file --brief --mime-type "${target_path}/${image_name}")
			case "${mime_type}" in
				"image/png")
					oxipng "${target_path}/${image_name}" ;;
				"image/jpeg")
					jpegoptim "${target_path}/${image_name}" ;;
				*) echo "${mime_type} not optimized for minimal size" ;;
			esac
		else
			echo "W: ${img} not found"
		fi
	done
done

# Sort the navigation
sort -o "${target}/${module_path}/nav.adoc" "${target}/${module_path}/nav.adoc"

# Generate the manual
pushd "${target}"
git init
git add .
git commit -a -m "Import manual"
npx antora site.yml
popd

exit 0
