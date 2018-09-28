#!/bin/bash

# Location of Apache conf file
APACHE_CONF=httpd.conf

# The current username
CURRENT_USERNAME=$(id -un)

# The current date and time, used for filenames
# https://unix.stackexchange.com/a/57592/260936
TODAY=`date +%Y-%m-%d.%H:%M:%S`
TODAY_SUFFIX=`date +%Y%m%d.%H%M%S`

# Checks if the given line exists in the specified file and replaces it.
# param: filename The file to search in
# param: term     Regex for finding the text to be replaced
# param: replace  Text to replace the matches
# param: explain  Text that is printed to stdout that explains what happened
function replaceline () {
    # empty case: file does not exist
    # https://stackoverflow.com/a/638980/1620794
    if [ ! -f $1 ]; then
        echo "replaceline() failed; file not found: $1"
        exit 1;
    fi

    # grep for the term in the file
    # $2 - term regex
    # $1 - path to file to be changed
    echo "grep term \"$2\" to find in file \"$1\""
    grep -q "$2" $1
    LINE_EXISTS=$?

    if [ "$LINE_EXISTS" -eq 0 ]; then
        # sed requires empty parameter after -i option on macOS
        # https://stackoverflow.com/a/16746032/1620794
        echo $4
        echo "s/$2/$3"
        sed -i '' "s/$2/$3" $1
        return $?
    fi

    echo "term \"$2\" not found. moving on..."
    return 1;
}

# 3. Apache Configuration
# Backup current Apache conf file
echo "Creating a backup of the Apache configuration file before continuing..."
cp -v "$APACHE_CONF.original" $APACHE_CONF
cp -v $APACHE_CONF "$APACHE_CONF.original.$TODAY_SUFFIX"

if [ ! $? -eq 0 ]; then
    echo "Could not successfully create a backup of the Apache conf file; stopping to prevent errors..."
    exit 1;
fi

# Change the default port of 8080 to 80
replaceline $APACHE_CONF '^Listen 8080$' 'Listen 80/' 'Changed Apache port to 80...'

# Change the DocumentRoot to /Users/CURRENT_USERNAME/Sites
mkdir -p "\/Users\/$CURRENT_USERNAME\/Sites/"
replaceline $APACHE_CONF '^DocumentRoot.*' "DocumentRoot \/Users\/$CURRENT_USERNAME\/Sites/" "Set DocumentRoot to /Users/$CURRENT_USERNAME/Sites..."

# Change the directory for the DocumentRoot to /Users/CURRENT_USERNAME/Sites
# TODO: Make this more flexible to replace this line without it being an exact match
# It should look for the first instance of '^<Directory.*' after '^DocumentRoot.*'; that way it can update the file every time
DOCUMENTROOT_LINE_NUM=$(grep -n '^DocumentRoot.*' $APACHE_CONF | cut -f1 -d:)
# echo $DOCUMENTROOT_LINE_NUM
replaceline $APACHE_CONF '^<Directory \"\/usr\/local\/var\/www\">$' "<Directory \/Users\/$CURRENT_USERNAME\/Sites>/" "Changed Apache root directory to /Users/$CURRENT_USERNAME/Sites..."

# Configure Apache root directory to allow overrides from .htaccess files
# TODO: This needs to look within the <Directory/> tag only
# Set AllowOverride All

# Enable the mod_rewrite module; if it is commented, only remove the first character
# If it doesn't exist, add it
LINE_NUM=$(grep -n 'LoadModule rewrite_module' $APACHE_CONF | cut -f1 -d:)
# https://stackoverflow.com/a/29161453/1620794 - deleting a single character