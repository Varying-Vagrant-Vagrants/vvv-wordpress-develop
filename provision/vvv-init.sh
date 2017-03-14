# Provision WordPress Develop

WP_TYPE=`get_config_value 'wp_type' "single"`

if [ "${WP_TYPE}" != "single" ]; then
  SRC_DOMAINS="src.wordpress-ms-develop.dev *.src.wordpress-ms-develop.dev ~^src\.wordpress-ms-develop\.\d+\.\d+\.\d+\.\d+\.xip\.io$"
  BUILD_DOMAINS="build.wordpress-ms-develop.dev *.build.wordpress-ms-develop.dev ~^build\.wordpress-ms-develop\.\d+\.\d+\.\d+\.\d+\.xip\.io$"
  SRC_DOMAIN="src.wordpress-ms-develop.dev"
  BUILD_DOMAIN="build.wordpress-ms-develop.dev"
else
  SRC_DOMAINS="src.wordpress-develop.dev *.src.wordpress-develop.dev ~^src\.wordpress-develop\.\d+\.\d+\.\d+\.\d+\.xip\.io$"
  BUILD_DOMAINS="build.wordpress-develop.dev *.build.wordpress-develop.dev ~^build\.wordpress-develop\.\d+\.\d+\.\d+\.\d+\.xip\.io$"
  SRC_DOMAIN="src.wordpress-develop.dev"
  BUILD_DOMAIN="build.wordpress-develop.dev"
fi

# Make a database, if we don't already have one
echo -e "\nCreating database 'wordpress_develop' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS wordpress_develop"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON wordpress_develop.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/src.error.log
touch ${VVV_PATH_TO_SITE}/log/src.access.log
touch ${VVV_PATH_TO_SITE}/log/build.access.log
touch ${VVV_PATH_TO_SITE}/log/build.access.log

# Checkout, install and configure WordPress trunk via develop.svn
if [[ ! -d "${VVV_PATH_TO_SITE}/public_html" ]]; then
  echo "Checking out WordPress trunk. See https://develop.svn.wordpress.org/trunk"
  noroot svn checkout "https://develop.svn.wordpress.org/trunk/" "/tmp/wordpress-develop"

  cd /tmp/wordpress-develop/src/

  echo "Installing local npm packages for ${SRC_DOMAIN}, this may take several minutes."
  noroot npm install

  echo "Initializing grunt and creating ${BUILD_DOMAIN}, this may take several minutes."
  noroot grunt

  echo "Moving WordPress develop to a shared directory, ${VVV_PATH_TO_SITE}/public_html"
  mv /tmp/wordpress-develop ${VVV_PATH_TO_SITE}/public_html

  cd ${VVV_PATH_TO_SITE}/public_html/src/
  echo "Creating wp-config.php for ${SRC_DOMAIN} and ${BUILD_DOMAIN}."
  noroot wp core config --dbname=wordpress_develop --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
// Match any requests made via xip.io.
if ( isset( \$_SERVER['HTTP_HOST'] ) && preg_match('/^(src|build)(.([a-z\-]+).)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(.xip.io)\z/', \$_SERVER['HTTP_HOST'] ) ) {
    define( 'WP_HOME', 'http://' . \$_SERVER['HTTP_HOST'] );
    define( 'WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST'] );
} else if ( 'build' === basename( dirname( __FILE__ ) ) ) {
// Allow (src|build).wordpress-develop.dev to share the same Database
    define( 'WP_HOME', 'http://' . str_replace( 'src.', 'build.', \$_SERVER['HTTP_HOST'] ) );
    define( 'WP_SITEURL', 'http://' . str_replace( 'src.', 'build.', \$_SERVER['HTTP_HOST'] ) );
}

define( 'WP_DEBUG', true );
PHP

  echo "Installing ${SRC_DOMAIN}."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url=${SRC_DOMAIN} --quiet --title="WordPress Develop" --admin_name=admin --admin_email="admin@local.dev" --admin_password="password"
  cp /srv/config/wordpress-config/wp-tests-config.php ${VVV_PATH_TO_SITE}/public_html/
  cd ${VVV_PATH_TO_SITE}/public_html/

else

  echo "Updating WordPress develop..."
  cd ${VVV_PATH_TO_SITE}/public_html/
  if [[ -e .svn ]]; then
    svn up
  else

    if [[ $(git rev-parse --abbrev-ref HEAD) == 'master' ]]; then
      git pull --no-edit git://develop.git.wordpress.org/ master
    else
      echo "Skip auto git pull on develop.git.wordpress.org since not on master branch"
    fi

  fi

  echo "Updating npm packages..."
  noroot npm install &>/dev/null
fi

if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/build" ]]; then
  echo "Initializing grunt in WordPress develop... This may take a few moments."
  cd ${VVV_PATH_TO_SITE}/public_html/
  grunt
fi

ln -sf ${VVV_PATH_TO_SITE}/bin/develop_git /home/vagrant/bin/develop_git

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{SRC_DOMAINS_HERE}}#${SRC_DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{BUILD_DOMAINS_HERE}}#${BUILD_DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{SRC_DOMAIN_HERE}}#${SRC_DOMAIN}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{BUILD_DOMAIN_HERE}}#${BUILD_DOMAIN}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
