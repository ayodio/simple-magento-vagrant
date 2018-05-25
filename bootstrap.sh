#!/usr/bin/env bash

SAMPLE_DATA=$1
MAGE_VERSION=$2
DATA_VERSION=$3
DOMAIN_NAME=$4
DEVELOPER_IP=$5
ADMIN_LOGIN=admin
ADMIN_PASSWORD=Password123


# Update Apt
# --------------------
apt-get -q update

# Install Apache & PHP
# --------------------

if [[ $MAGE_VERSION == 1* ]]
then
echo "magento1"
# Magento 1
# --------------------
apt-get -q install -y apache2
apt-get -q install -y php5
apt-get -q install -y libapache2-mod-php5
apt-get -q install -y php5-mysqlnd php5-curl php5-gd php5-intl php-pear php5-imap php5-mcrypt php5-ming php5-ps php5-pspell php5-recode php5-sqlite php5-tidy php5-xmlrpc php5-xsl php-soap php5-cli php5-dev php5-xdebug
php5enmod mcrypt
fi

if [[ $MAGE_VERSION == 2* ]]
then
echo "magento2"
# Magento 2
# --------------------
apt-get -q -y update
add-apt-repository ppa:ondrej/php
apt-get -q -y update
apt-get -q install -y php7.1 libapache2-mod-php7.1 php7.1-common php7.1-gd php7.1-mysql php7.1-mcrypt php7.1-curl php7.1-intl php7.1-xsl php7.1-mbstring php7.1-zip php7.1-bcmath php7.1-iconv php7.1-soap

##changer la memory limit à 512
phpmemory_limit=512M
sed -i 's/memory_limit = 128M/memory_limit = '${phpmemory_limit}'/' /etc/php/7.1/apache2/php.ini
fi

# Delete default apache web dir and symlink mounted vagrant dir from host machine
# --------------------r
rm -rf /var/www/magento
sudo mkdir /vagrant
sudo mkdir /vagrant/httpdocs
ln -fs /vagrant/httpdocs /var/www/magento

# Active xdebug
# --------------------
XDEBUG_SO=`find /usr/lib/php5/ -name xdebug.so`
XDEBUG="
[xdebug]
xdebug.remote_enable=1
xdebug.remote_host=$DEVELOPER_IP
xdebug.remote_port=9000
xdebug.remote_handler=dbgp
zend_extension=$XDEBUG_SO"

echo "$XDEBUG" >> /etc/php5/apache2/php.ini

# Replace contents of default Apache vhost
# --------------------
VHOST="NameVirtualHost *:80
<VirtualHost *:80>
  DocumentRoot '/var/www/magento'
  ServerName $DOMAIN_NAME.local
  ServerAlias www.$DOMAIN_NAME.local
  <Directory '/var/www/magento'>
    AllowOverride All
  </Directory>
</VirtualHost>"

echo "$VHOST" > /etc/apache2/sites-enabled/000-default.conf

a2enmod rewrite
service apache2 restart

# Mysql
# --------------------
# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive
# Install MySQL quietly
if [[ $MAGE_VERSION == 2* ]]
then
apt-get -q -y install mysql-server-5.6
else
apt-get -q -y install mysql-server-5.5
fi

mysql -u root -e "CREATE DATABASE IF NOT EXISTS magentodb"
mysql -u root -e "GRANT ALL PRIVILEGES ON magentodb.* TO 'magentouser'@'localhost' IDENTIFIED BY 'password'"
mysql -u root -e "FLUSH PRIVILEGES"


# Magento
# --------------------
# http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/installing_magento_via_shell_ssh

# Download and extract
#if [[ ! -f "/vagrant/httpdocs/index.php" ]]; then
  cd /vagrant/httpdocs
  if [[ ! -f "/vagrant/assets/${MAGE_VERSION}.tar.gz" ]]; then
    if [[ $MAGE_VERSION == 2* ]]
    then
    wget -nv https://github.com/magento/magento2/archive/${MAGE_VERSION}.tar.gz
    sudo cp ${MAGE_VERSION}.tar.gz ../assets/.
    else
    wget -nv https://github.com/OpenMage/magento-mirror/archive/${MAGE_VERSION}.tar.gz
    sudo cp ${MAGE_VERSION}.tar.gz ../assets/.
    fi
  else
    sudo cp ../assets/${MAGE_VERSION}.tar.gz .
  fi
  tar -zxf ${MAGE_VERSION}.tar.gz
  if [[ $MAGE_VERSION == 2* ]]
  then
  mv magento2-${MAGE_VERSION}/* magento2-${MAGE_VERSION}/.* .
  else
  mv magento-mirror-${MAGE_VERSION}/* magento-mirror-${MAGE_VERSION}/.htaccess .
  sed -i 's#<pdo_mysql/>#<pdo_mysql>1</pdo_mysql>#g' app/code/core/Mage/Install/etc/config.xml
  fi
  chmod -R o+w media var
  chmod o+w app/etc
  # Clean up downloaded file and extracted dir
  rm -rf magento*
  rm ${MAGE_VERSION}.tar.gz
#fi


# Sample Data
if [[ $SAMPLE_DATA == "true" ]]; then
  if [[ $MAGE_VERSION == 2* ]]
  then
    if [[ ! -f "/vagrant/assets/magento-sample-data-${DATA_VERSION}.tar.gz" ]]; then
      wget https://github.com/magento/magento2-sample-data/archive/${DATA_VERSION}.tar.gz
      mv ${DATA_VERSION}.tar.gz /vagrant/assets/magento-sample-data-${DATA_VERSION}.tar.gz
    fi
    tar -zxf ../assets/magento-sample-data-2.2.3.tar.gz
    cp -R magento2-sample-data-${DATA_VERSION}/* .
    rm -rf magento2-sample-data-${DATA_VERSION}/
    rmdir magento2-sample-data-${DATA_VERSION}
  else
   cd /vagrant
   if [[ ! -f "/vagrant/assets/magento-sample-data-${DATA_VERSION}.tar.gz" ]]; then
     # Only download sample data if we need to
     wget -nv http://mirror.gunah.eu/magento/sample-data/magento-sample-data-${DATA_VERSION}.tar.gz
     cp magento-sample-data-${DATA_VERSION}.tar.gz assets/.
   else
     cp assets/magento-sample-data-${DATA_VERSION}.tar.gz .
   fi

   tar -zxf magento-sample-data-${DATA_VERSION}.tar.gz
   cp -R magento-sample-data-${DATA_VERSION}/media/* httpdocs/media/
   cp -R magento-sample-data-${DATA_VERSION}/skin/*  httpdocs/skin/
   mysql -u root magentodb < magento-sample-data-${DATA_VERSION}/magento_sample_data_for_${DATA_VERSION}.sql
   rm -rf magento-sample-data-${DATA_VERSION}
   rm magento-sample-data-${DATA_VERSION}.tar.gz
   sudo chmod 777 -R httpdocs/media/
 fi
fi


# Run installer
if [[ $MAGE_VERSION == 2* ]]
then
    echo "magento 2 - installation"
    cd /vagrant/httpdocs
    # install composer
    sudo curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer

    sudo chown -R www-data:www-data /vagrant/httpdocs/*
    sudo chown -R www-data:www-data /vagrant/httpdocs/.*
    sudo chmod -R 777 /vagrant/httpdocs/

    sudo -u www-data composer require Imaginaerum/magento2-language-fr-fr:*
    sudo -u www-data composer install

    install_cmd="setup:install \
    --db-host=localhost \
    --db-name=magentodb \
    --db-user=magentouser \
    --db-password=password \
    --backend-frontname=admin \
    --base-url=http://${DOMAIN_NAME}.local/ \
    --language=fr_FR \
    --timezone=Europe/Paris \
    --currency=EUR \
    --admin-lastname=Owner \
    --admin-firstname=Store \
    --admin-email=admin@example.com \
    --admin-user=${ADMIN_LOGIN} \
    --admin-password=${ADMIN_PASSWORD} \
    --cleanup-database \
    --use-rewrites=1"

    echo ${install_cmd}
    sudo -u www-data php /vagrant/httpdocs/bin/magento ${install_cmd}
    sudo -u www-data php /vagrant/httpdocs/bin/magento cron:install
    sudo -u www-data php /vagrant/httpdocs/bin/magento cron:run
else
    if [ ! -f "/vagrant/httpdocs/app/etc/local.xml" ]; then
      cd /vagrant/httpdocs
      sudo /usr/bin/php -f install.php -- --license_agreement_accepted yes --locale fr_FR --timezone "Europe/Paris" --default_currency EUR --db_host localhost --db_name magentodb --db_user magentouser --db_pass password --url "http://"${DOMAIN_NAME}".local/" --use_rewrites yes --use_secure no --secure_base_url "http://"${DOMAIN_NAME}".local/" --use_secure_admin no --skip_url_validation yes --admin_lastname Owner --admin_firstname Store --admin_email "admin@example.com" --admin_username $ADMIN_LOGIN --admin_password $ADMIN_PASSWORD
      /usr/bin/php -f shell/indexer.php reindexall
    fi
fi

# Install n98-magerun
# --------------------
cd /vagrant/httpdocs
if [[ $MAGE_VERSION == 2* ]]
    then
        wget -nv https://files.magerun.net/n98-magerun2.phar
        chmod +x ./n98-magerun2.phar
        sudo mv ./n98-magerun2.phar /usr/local/bin/
    else
        wget -nv https://files.magerun.net/n98-magerun.phar
        chmod +x ./n98-magerun.phar
        sudo mv ./n98-magerun.phar /usr/local/bin/
fi


# after install
sudo cp -r /vagrant/code/* /vagrant/httpdocs/
sudo chown -R www-data:www-data /vagrant/httpdocs/*
sudo chown -R www-data:www-data /vagrant/httpdocs/.*
sudo chmod -R 777 /vagrant/httpdocs/
if [[ $MAGE_VERSION == 2* ]]

    then
        sudo -u www-data n98-magerun2.phar customer:create atr+client@atolcd.com $ADMIN_PASSWORD Antoine Trapet
    else
        n98-magerun.phar customer:create atr+client@atolcd.com $ADMIN_PASSWORD Antoine Trapet base
        n98-magerun.phar dev:merge-js --on --global
        n98-magerun.phar dev:merge-css --on --global
        n98-magerun.phar dev:log --on --global
        n98-magerun.phar cache:dir:flush
fi