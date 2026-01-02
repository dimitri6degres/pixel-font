#!/bin/sh

#  Version.sh
#  Teamup
#
#  Created by dim on 01/07/2024.
#  Copyright © 2024 6°designers. All rights reserved.

#!/bin/bash
# This script is designed to increment the build number consistently across all
# targets.

# Navigating to the 'carbonwatchuk' directory inside the source root.
cd "$SRCROOT/$PRODUCT_NAME"

# Parse the 'Config.xcconfig' file to retrieve the previous build number.
# The 'awk' command is used to find the line containing "BUILD_NUMBER"
# and the 'tr' command is used to remove any spaces.
previous_build_number=$(awk -F "=" '/VERSION/ {print $2}' Config.xcconfig | tr -d ' ')

# Extract the date part and the counter part from the previous build number.
previous_version="${previous_build_number:0:4}"
counter="${previous_build_number:4}"

# If the current date matches the date from the previous build number,
# increment the counter. Otherwise, reset the counter to 1.
new_counter=$((${counter} + 1))

# Combine the current date and the new counter to create the new build number.
new_build_number="${previous_version}$new_counter"

# Use 'sed' command to replace the previous build number with the new build
# number in the 'Config.xcconfig' file.
sed -i -e "/VERSION =/ s/= .*/= $new_build_number/" Config.xcconfig

# Remove the backup file created by 'sed' command.
rm -f Config.xcconfig-e
