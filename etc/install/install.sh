#!/bin/bash

set -ex

# Installation settings
PROJECT_NAME=""
PROJECT_DIR=/vagrant/$PROJECT_NAME

PGSQL_VERSION=10

if [ ! -f /home/vagrant/.locales ]; then
    # Need to fix locale so that Postgres creates databases in UTF-8
    cp -p $PROJECT_DIR/etc/install/etc-bash.bashrc /etc/bash.bashrc
    locale-gen en_US.UTF-8
    #dpkg-reconfigure locales
    touch /home/vagrant/.locales
fi

export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# wget -qO - https://deb.packager.io/key | sudo apt-key add -
# echo "deb https://deb.packager.io/gh/tessi/openproject precise feature/pkgr" | sudo tee /etc/apt/sources.list.d/openproject.list

wget -qO- https://dl.packager.io/srv/opf/openproject/key | apt-key add -
add-apt-repository universe
wget -O /etc/apt/sources.list.d/openproject.list https://dl.packager.io/srv/opf/openproject/stable/10/installer/ubuntu/18.04.repo

# Install essential packages from Apt
apt-get update -y

apt-get install -y openproject

# Postgresql
if ! command -v psql; then
    apt-get install -y postgresql-$PGSQL_VERSION libpq-dev

    cp $PROJECT_DIR/etc/install/pg_hba.conf \
        /etc/postgresql/$PGSQL_VERSION/main/
        /etc/init.d/postgresql reload
fi


# Git (we'd rather avoid people keeping credentials for git commits
# in the repo, but sometimes we need it for pip requirements that
# aren't in PyPI)
if ! command -v git ; then
    apt-get install -y git
fi

# mcedit
if ! command -v mcedit; then
    apt-get install -y mc
fi

# nginx
if ! command -v nginx ; then
    apt-get install -y nginx
    rm /etc/nginx/sites-enabled/default
    cp $PROJECT_DIR/etc/install/nginx.default.conf /etc/nginx/sites-enabled/default
    service nginx restart
fi

# now install openproject
if ! command -v openproject; then
    # apt-get install -y openproject*=3.0.1-1400061402.f476e5c.precise

    # create database
    createuser -U postgres -S -D -R openproject
    createdb -U postgres -O openproject openproject

    # configure openproject
    openproject config:set SECRET_TOKEN=$(openproject run rake secret | tail -1)
    openproject config:set DATABASE_URL=postgres://openproject@localhost/openproject

    # run initialization
    openproject run rake db:migrate
    openproject run rake db:seed
    openproject scale web=1 worker=1
    service openproject restart
fi

function install() {
    cp $PROJECT_DIR/etc/install/${1} /usr/sbin/
    chmod +x /usr/sbin/${1}
}

install update-plugins.sh
install backup-database.sh
install restore-database.sh

/usr/sbin/update-plugins.sh

if [ ! -f $PROJECT_DIR/.crontab.updated ] ; then
    crontab -u openproject ${PROJECT_DIR}/etc/install/crontab
    touch $PROJECT_DIR/.crontab.updated
fi

if [ -d $PROJECT_DIR/dumps ]; then
    LAST_DUMP=`find $PROJECT_DIR/dumps -type f | sort | tail -n1`
    service openproject stop
    /usr/sbin/restore-database.sh ${LAST_DUMP}
    service openproject start
fi
