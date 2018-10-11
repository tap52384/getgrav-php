#!/bin/bash

# Based on guide posted here:
# https://getgrav.org/blog/macos-mojave-apache-multiple-php-versions

APACHE_CONF=/usr/local/etc/httpd/httpd.conf

# Get the version of macOS (Mojave is 10.14)
MACOS_VERSION=$(defaults read loginwindow SystemVersionStampAsString)

# Detect if Homebrew package is installed
# https://stackoverflow.com/a/20802425/1620794
# brew ls --versions $1

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
        sed -i "" "s/$2/$3" $1
        return $?
    fi

    echo "term \"$2\" not found. moving on..."
    return 1;
}

# 0. Detect if certain requirements are already installed
which brew > /dev/null
BREW_INSTALLED=$?

# The current date and time, used for filenames
# https://unix.stackexchange.com/a/57592/260936
TODAY=`date +%Y-%m-%d.%H:%M:%S`
TODAY_SUFFIX=`date +%Y%m%d.%H%M%S`

# The current username
CURRENT_USERNAME=$(id -un)

# Check whether Ruby is installed (should be by default on macOS)
which ruby > /dev/null
RUBY_INSTALLED=$?

# 0. If Ruby is unavailable, then you have a big problem
if [ ! "$RUBY_INSTALLED" -eq 0 ]; then
    echo "Ruby is not installed which is required to install Homebrew; exiting..."
    exit 1;
fi

# 1. If Homebrew is not installed, go ahead and install it
if [ ! "$BREW_INSTALLED" -eq 0 ]; then
    echo "Homebrew not installed; installing now..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    which brew > /dev/null
    BREW_INSTALLED=$?
else
    echo "Homebrew is already installed."
fi

# Checks again to make sure Homebrew is installed
if [ ! "$BREW_INSTALLED" -eq 0 ]; then
    echo "Homebrew unavailable and installation failed; stopping here..."
    exit 1;
fi

# 2. Install Apache 2.4 via Homebrew
echo "Shutting down Apache..."
sudo apachectl stop
echo "Unloading native Apache service..."
sudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist 2>/dev/null

echo "Installing required Homebrew formulas..."
brew update

if [ "$MACOS_VERSION" = "10.14" ]; then
        brew install libiconv
        brew install openldap
fi

brew install archey
brew install autoconf
brew install dnsmasq
brew install httpd
brew install libyaml
brew install mariadb
brew install php@5.6
brew install php@7.0
brew install php@7.1
brew install php@7.2

echo "Setting Apache to auto-start upon system boot for all users..."
sudo brew services start httpd

echo "Setting MariaDB to auto-start upon system boot for all users..."
sudo brew services start mariadb

echo "Setting DNSMasq to auto-start upon system boot for all users..."
# Set up Apache Virtual Hosts
echo 'address=/.test/127.0.0.1' > /usr/local/etc/dnsmasq.conf
sudo mkdir -v /etc/resolver
sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/test'
sudo brew services start dnsmasq

# PHP Switcher Script
which sphp > /dev/null
SPHP_INSTALLED=$?

if [ ! "$BREW_INSTALLED" -eq 0 ]; then
    echo "PHP Switcher Script not installed; downloading and installing now..."
    curl -L https://gist.githubusercontent.com/rhukster/f4c04f1bf59e0b74e335ee5d186a98e2/raw > /usr/local/bin/sphp
    chmod +x /usr/local/bin/sphp
else
    echo "PHP Switcher Script is already installed."
fi
sphp 5.6

# Install xdebug toggler
which xdebug > /dev/null
XDEBUG_TOGGLER_INSTALLED=$?

if [ ! "$XDEBUG_TOGGLER_INSTALLED" -eq 0 ]; then
    echo "XDebug Toggler not installed; downloading and installing now..."
    curl -L https://gist.githubusercontent.com/rhukster/073a2c1270ccb2c6868e7aced92001cf/raw > /usr/local/bin/xdebug
    chmod +x /usr/local/bin/xdebug
else
    echo "XDebug Toggler is already installed."
fi

# Install PHP Composer
which composer > /dev/null
COMPOSER_INSTALLED=$?

if [ ! "$COMPOSER_INSTALLED" -eq 0 ]; then
    echo "Composer not installed; downloading and installing now..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    chmod +x /usr/local/bin/composer
else
    echo "Composer is already installed."
fi

LOCALHOST_8080_RESPONSE=$(curl --write-out %{http_code} --silent --insecure  --output /dev/null http://localhost:8080)
LOCALHOST_80_RESPONSE=$(curl --write-out %{http_code} --silent --insecure  --output /dev/null http://localhost:80)

if [ "$LOCALHOST_8080_RESPONSE" -lt 200 ] && [ "$LOCALHOST_8080_RESPONSE" -gt 204 ] && [ "$LOCALHOST_80_RESPONSE" -lt 200 ] && [ "$LOCALHOST_80_RESPONSE" -gt 204 ]; then
    echo "Localhost unavailable for both port 80 and 8080; stopping..."
    exit 1;
fi

echo "Localhost is available; Apache is currently running..."

# 3. Apache Configuration
# Backup current Apache conf file
echo "Creating a backup of the Apache configuration file before continuing..."
cp -v $APACHE_CONF "$APACHE_CONF.original.$TODAY_SUFFIX"

if [ ! $? -eq 0 ]; then
    echo "Could not successfully create a backup of the Apache conf file; stopping to prevent errors..."
    exit 1;
fi

# Change the default port of 8080 to 80
replaceline $APACHE_CONF '^Listen 8080$' 'Listen 80/' 'Change Apache port to 80...'

# Change the DocumentRoot to /Users/CURRENT_USERNAME/Sites
mkdir -p "\/Users\/$CURRENT_USERNAME\/Sites/"
replaceline $APACHE_CONF '^DocumentRoot.*' "DocumentRoot \/Users\/$CURRENT_USERNAME\/Sites/" "Set DocumentRoot to /Users/$CURRENT_USERNAME/Sites..."

# Set the servername to localhost
replaceline $APACHE_CONF '#ServerName www.example.com:8080' 'ServerName localhost/'
replaceline $APACHE_CONF '^ServerName.*' 'ServerName localhost' 'Set ServerName to "localhost"...'

# Enable the mod_rewrite and vhost_alias_module module
replaceline $APACHE_CONF '^#LoadModule rewrite_module.*' 'LoadModule rewrite_module lib/httpd/modules/mod_rewrite.so' 'Enabling the "mod_rewrite" module...'
replaceline $APACHE_CONF '^#LoadModule whost_alias_module.*' 'LoadModule vhost_alias_module lib/httpd/modules/mod_vhost_alias.so' 'Enabling the "vhost_alias_module" module...'
replaceline $APACHE_CONF 'httpd-vhosts.conf$' 'Include /usr/local/etc/httpd/extra/httpd-vhosts.conf' 'Set the config file for the vhosts module...'

# Set user and group appropriately
replaceline $APACHE_CONF '^User _www' "User $CURRENT_USERNAME" "Set Apache user to $CURRENT_USERNAME..."
replaceline $APACHE_CONF '^User daemon' "User $CURRENT_USERNAME"
replaceline $APACHE_CONF '^Group _www' 'Group staff' 'Set Apache group to "staff"...'
replaceline $APACHE_CONF '^Group daemon' 'Group staff'

# Set index.php to load phpinfo() for the current PHP version
echo "<?php phpinfo();" > ~/Sites/index.php

# TODO: Set AllowOverride All in the correct place

# TODO: Change the directory for the DocumentRoot to /Users/CURRENT_USERNAME/Sites
# starts with "<Directory " but does not end with "/>" or " "/usr/local/var/www/cgi-bin">"
DOCUMENTROOT_LINE_NUM=$(grep -n '^DocumentRoot.*' /usr/local/etc/httpd/httpd.conf | cut -f1 -d:)
# grep for a line that starts with a string but does not start with another
# parentheses and pipe had to be escaped in grep regex
# https://unix.stackexchange.com/a/21765/260936
# regex for string that starts with one thing but does not end with another
# https://stackoverflow.com/questions/10849682/regex-for-string-that-starts-but-doesnt-end-with
# this line selects the standard one or the one that matches the current username
grep -n '^<Directory.*\("/usr/local/var/www"\|/Users/patricklewis/Sites\)>$' httpd.conf

# this line select the first line that does not end with "/>" or " "/usr/local/var/www/cgi-bin">"
#sed -i '' "s/^<Directory.*\(\"\/usr\/local\/var\/www\"\|\/Users\/$CURRENT_USERNAME\/Sites\)>$/<Directory \/Users\/$CURRENT_USERNAME\/Sites>/" $APACHE_CONF



# TODO: Add the php modules for PHP 5.6, 7.0, 7.1 and 7.2 at the end of the list of "LoadModule",
# only if they do not already exist


# TODO: Set the DirectoryIndex to look for index.php and index.html, in that order

# TODO: Add a handler for all files that match *.php as application/x-httpd-php

# Turn off opcache for PHP 5.6 in order for it to work properly
# https://discourse.brew.sh/t/segmentation-fault-on-mojave-http24-php56/3043/7
# Comments out all lines using a semi-colon
# https://stackoverflow.com/a/2099478/1620794
#replaceline /usr/local/etc/php/5.6/conf.d/ext-opcache.ini '^opcache.enabled=.*' 'opcache.enabled=0' 'Disabling opcache on PHP 5.6...'
echo "Disabling opcache on PHP 5.6..."
sed -i '' -e '/^;/! s/^/;/' /usr/local/etc/php/5.6/conf.d/ext-opcache.ini

# Add config files for apcu, xdebug, and yaml PHP packages
# Replace the specific line in a text file with a string
# https://stackoverflow.com/a/13438118/1620794
touch -a /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
# add blank lines to the config file
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '1s/.*/[apcu]/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '2s/.*/extension="apcu.so"/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '3s/.*/apc.enabled=1/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '4s/.*/apc.shm_size=64M/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '5s/.*/apc.ttl=7200/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini
sed -i '' '6s/.*/apc.enable_cli=1/' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini

# remove any blank lines from the config file
# https://stackoverflow.com/a/16414489/1620794
sed -i "" '/^[[:space:]]*$/d' /usr/local/etc/php/5.6/conf.d/ext-apcu.ini

touch -a /usr/local/etc/php/5.6/conf.d/ext-yaml.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-yaml.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-yaml.ini
sed -i '' '1s/.*/[yaml]/' /usr/local/etc/php/5.6/conf.d/ext-yaml.ini
sed -i '' '2s/.*/extension="yaml.so"/' /usr/local/etc/php/5.6/conf.d/ext-yaml.ini

# remove any blank lines from the config file
# https://stackoverflow.com/a/16414489/1620794
sed -i "" '/^[[:space:]]*$/d' /usr/local/etc/php/5.6/conf.d/ext-yaml.ini

touch -a /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
echo "" >> /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '1s/.*/[xdebug]/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '2s/.*/zend_extension="xdebug.so"/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '3s/.*/xdebug.remote_enable=1/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '4s/.*/xdebug.remote_host=localhost/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '5s/.*/xdebug.remote_handler=dbgp/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini
sed -i '' '6s/.*/xdebug.remote_port=9000/' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini

# remove any blank lines from the config file
# https://stackoverflow.com/a/16414489/1620794
sed -i "" '/^[[:space:]]*$/d' /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini


# Install PHP packages
pecl channel-update pecl.php.net
printf "\n" | pecl install apcu-4.0.11
printf "\n" | pecl install yaml-1.3.1
pecl install xdebug-2.5.5

# Remove the references to apcu, yaml, and xdebug from php.ini for PHP 5.6
echo "Removed references to apcu, xdebug, and yaml from php.ini for PHP 5.6..."
sed -e '/^zend_extension="xdebug.so"/ s/^zend_extension="xdebug.so"//g' -i '' /usr/local/etc/php/5.6/php.ini
sed -e '/^extension="yaml.so"/ s/^extension="yaml.so"//g' -i '' /usr/local/etc/php/5.6/php.ini
sed -e '/^extension="apcu.so"/ s/^extension="apcu.so"//g' -i '' /usr/local/etc/php/5.6/php.ini

# this could be a function so that it could only be written once
## declare an array variable
declare -a SEVEN_PLUS=("7.0", "7.1", "7.2")

for i in "${SEVEN_PLUS[@]}"
do
    printf "About to switch to PHP $i...\n"
    sphp $i
    # install apcu, yaml, and xdebug for this version of PHP
    pecl uninstall -r apcu
    printf "\n" | pecl install apcu
    pecl uninstall -r yaml
    printf "\n" | pecl install yaml
    pecl uninstall -r xdebug
    pecl install xdebug

    # Remove the references to apcu, yaml, and xdebug from php.ini for each version
    echo "Removed references to apcu, xdebug, and yaml from php.ini for PHP $i..."
    sed -e '/^zend_extension="xdebug.so"/ s/^zend_extension="xdebug.so"//g' -i '' "/usr/local/etc/php/$i/php.ini"
    sed -e '/^extension="yaml.so"/ s/^extension="yaml.so"//g' -i '' "/usr/local/etc/php/$i/php.ini"
    sed -e '/^extension="apcu.so"/ s/^extension="apcu.so"//g' -i '' "/usr/local/etc/php/$i/php.ini"

    # use symlinks to use the PHP 5.6 config file for the current version
    echo "Create symlinks to PHP 5.6 ini files for PHP $i...\n"
    ln -s /usr/local/etc/php/5.6/conf.d/ext-yaml.ini "/usr/local/etc/php/$i/conf.d/ext-yaml.ini"
    ln -s /usr/local/etc/php/5.6/conf.d/ext-apcu.ini "/usr/local/etc/php/$i/conf.d/ext-apcu.ini"
    ln -s /usr/local/etc/php/5.6/conf.d/ext-xdebug.ini "/usr/local/etc/php/$i/conf.d/ext-xdebug.ini"

    # Turn xdebug on
    xdebug on
done