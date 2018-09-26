#!/bin/bash

APACHE_CONF=/usr/local/etc/httpd/httpd.conf

# Checks whether Homebrew is installed or not
function checkBrew {
    installed brew
    BREW_INSTALLED=$?
}

# Checks whether the specified application is available in the $PATH
function installed() {
    # empty case: empty string
    if [ -z "$1" ]; then
        return 1;
    fi

    # uses which to see if the command is in the $PATH
    which $1 > /dev/null
    return $?
}

# Checks if the given line exists in the specified file and replaces it.
# param: filename The file to search in
# param: needle   Regex for finding the text to be replaced
# param: haystack Text to replace the matches
# param: explain  Text that is printed to stdout that explains what happened
function replaceline () {
    # empty case: file does not exist
    # https://stackoverflow.com/a/638980/1620794
    if [ ! -f $1 ]; then
        echo "replaceline() failed; file not found: $1"
        exit() { return 1; }
    fi

    # grep for the needle in the file
    # $2 - needle regex
    # $1 - path to file to be changed
    echo "grep needle \"$2\" to find in file \"$1\""
    grep -q "$2" $1
    LINE_EXISTS=$?

    if [ "$LINE_EXISTS" -eq 0 ]; then
        # sed requires empty parameter after -i option on macOS
        # https://stackoverflow.com/a/16746032/1620794
        echo $4
        sed -i "" "s/$2/$3" $1
        return $?
    fi

    echo "needle \"$2\" not found. moving on..."
    return 1;
}

# 0. Detect if certain requirements are already installed
checkBrew

# The current date and time, used for filenames
# https://unix.stackexchange.com/a/57592/260936
TODAY=`date +%Y-%m-%d.%H:%M:%S`
TODAY_SUFFIX=`date +%Y%m%d.%H%M%S`

# The current username
CURRENT_USERNAME=$(id -un)

# Check whether Ruby is installed (should be by default on macOS)
which ruby > /dev/null
RUBY_INSTALLED=$?

APACHE_LOCATION=$(which apachectl)

# 1. If Homebrew is not installed, go ahead and install it
if [ "$BREW_INSTALLED" -eq 1 ]; then
    echo "Homebrew not installed; installing now..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
    echo "Homebrew is already installed."
fi

# Checks again to make sure Homebrew is installed
checkBrew
if [ "$BREW_INSTALLED" -eq 1 ]; then
    echo "Homebrew unavailable and installation failed; stopping here..."
    exit() { return 1; }
fi

# 2. Install Apache 2.4 via Homebrew
echo "Shutting down Apache..."
sudo apachectl stop
echo "Unloading native Apache service..."
sudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist 2>/dev/null

# Detect if Homebrew package is installed
# https://stackoverflow.com/a/20802425/1620794
brew ls --versions httpd
BREW_HTTPD_INSTALLED=$?

if [ "$BREW_HTTPD_INSTALLED" -eq 1 ]; then
    echo "Installing httpd formula (Apache)..."
    brew install httpd
else
    echo "The httpd formula (Apache) is already installed via Homebrew"
fi

echo "Setting Apache to auto-start upon system boot..."
sudo brew services start httpd

LOCALHOST_8080_RESPONSE=$(curl --write-out %{http_code} --silent --insecure  --output /dev/null http://localhost:8080)
LOCALHOST_80_RESPONSE=$(curl --write-out %{http_code} --silent --insecure  --output /dev/null http://localhost:80)

if [ "$LOCALHOST_8080_RESPONSE" -lt 200 ] && [ "$LOCALHOST_8080_RESPONSE" -gt 204 ] && [ "$LOCALHOST_80_RESPONSE" -lt 200 ] && [ "$LOCALHOST_80_RESPONSE" -gt 204 ]; then
    echo "Localhost unavailable for both port 80 and 8080; stopping..."
    exit() { return 1; }
fi

echo "Localhost is available; Apache is currently running..."

# 3. Apache Configuration
# Backup current Apache conf file
echo "Creating a backup of the Apache configuration file before continuing..."
cp -v $APACHE_CONF "$APACHE_CONF.original.$TODAY_SUFFIX"

if [ ! $? -eq 0 ]; then
    echo "Could not successfully create a backup of the Apache conf file; stopping to prevent errors..."
    exit() { return 1; }
fi

# Change the default port of 8080 to 80
replaceline $APACHE_CONF '^Listen 8080$' 'Listen 80/' 'Change Apache port to 80...'

# Change the DocumentRoot to /Users/CURRENT_USERNAME/Sites
mkdir "\/Users\/$CURRENT_USERNAME\/Sites/"
replaceline $APACHE_CONF '^DocumentRoot.*' "DocumentRoot \/Users\/$CURRENT_USERNAME\/Sites/" "Set DocumentRoot to /Users/$CURRENT_USERNAME/Sites..."

# Change the directory for the DocumentRoot to /Users/CURRENT_USERNAME/Sites
DOCUMENTROOT_LINE_NUM=$(grep -n '^DocumentRoot.*' /usr/local/etc/httpd/httpd.conf | cut -f1 -d:)
