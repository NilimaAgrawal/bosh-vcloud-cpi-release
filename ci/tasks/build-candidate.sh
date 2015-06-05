#!/usr/bin/env bash

set -e

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

semver=`cat version-semver/number`

mkdir out

cd bosh-cpi-release

echo "installing the latest bosh_cli"
gem install bosh_cli --no-ri --no-rdoc

echo "using bosh CLI version..."
bosh version

cpi_release_name="bosh-vcloud-cpi"

echo "building CPI release..."
bosh create release --name $cpi_release_name --version $semver --with-tarball

mv dev_releases/$cpi_release_name/$cpi_release_name-$semver.tgz ../out/
