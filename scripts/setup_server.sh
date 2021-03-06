#!/bin/bash

# exit if an error occurs in any simple command
set -e
# exit if an error occurs in a pipeline
set -o pipefail

usage() {
    echo "Usage: `basename $0` server_type rds_instance_ip_address"
    echo "       server_type is one of torquebox, torquebox_1, trinidad, glassfish,"
    echo "                             unicorn, unicorn_ree, unicorn_19, passenger,"
    echo "                             passenger_ree, passenger_19, or thin"
    echo "       rds_instance_ip_address is the IP address of the Amazon RDS instance"
    exit 1
}

[[ $# -ne 2 ]] && usage

SERVER_TYPE=$1
RDS_IP=$2

# Create writable directory under /mnt because the root
# partition isn't large on EC2 instances
sudo mkdir /mnt/data
sudo chmod 777 /mnt/data
cd /mnt/data

# Install necessary RPMs
sudo yum install -y erlang git screen

# Clone SpeedMetal
git clone git://github.com/torquebox/speedmetal.git

# Add /etc/hosts entry for our RDS instance
echo "$RDS_IP database" | sudo tee -a /etc/hosts

# Open up iptables
sudo iptables -I INPUT -p tcp -j ACCEPT
sudo iptables -I INPUT -p udp -j ACCEPT


install_java7() {
    sudo yum install -y wget
    wget http://download.oracle.com/otn-pub/java/jdk/7u2-b13/jdk-7u2-linux-x64.rpm
    sudo yum install jdk-7u2-linux-x64.rpm 
}

install_ruby() {
    sudo yum install -y ruby ruby-devel rubygems make gcc gcc-c++ \
        curl-devel openssl-devel zlib-devel
}

install_jruby() {
    # Install necessary RPMs
    sudo yum install -y java-1.6.0-openjdk java-1.6.0-openjdk-devel wget
    # Install JRuby
    wget http://jruby.org.s3.amazonaws.com/downloads/1.6.4/jruby-bin-1.6.4.tar.gz
    tar xf jruby-bin-1.6.4.tar.gz
    echo "export JRUBY_HOME=/mnt/data/jruby-1.6.4" >> ~/.bash_profile
    echo "export PATH=\$JRUBY_HOME/bin:\$PATH" >> ~/.bash_profile
    source ~/.bash_profile
    jruby -S gem install jruby-openssl
}

install_ree() {
    sudo yum install -y patch wget
    wget http://rubyenterpriseedition.googlecode.com/files/ruby-enterprise-1.8.7-2011.03.tar.gz
    tar xzf ruby-enterprise-1.8.7-2011.03.tar.gz
    PREFIX=/mnt/data/ree
    cd ruby-enterprise-1.8.7-2011.03/source/distro/google-perftools-1.7/
    ./configure --prefix=$PREFIX --disable-dependency-tracking
    make libtcmalloc_minimal.la
    mkdir -p $PREFIX/lib
    cp -Rpf .libs/libtcmalloc_minimal*.so* $PREFIX/lib/
    cd ../..
    ./configure --prefix=$PREFIX --enable-mbari-api CFLAGS='-g -O2'
    sed -i 's/^LIBS = /LIBS = $(PRELIBS) /' Makefile
    make PRELIBS="-Wl,-rpath,$PREFIX/lib -L$PREFIX/lib -ltcmalloc_minimal"
    sudo make install
    sudo mv /usr/bin/ruby /usr/bin/ruby.old
    sudo cp $PREFIX/bin/ruby /usr/bin/
    cd ../..
    echo "export PATH=$PREFIX/bin:\$PATH" >> ~/.bash_profile
    source ~/.bash_profile
    # Install RubyGems < 1.5.x to work w/ Redmine
    wget http://production.cf.rubygems.org/rubygems/rubygems-1.4.2.tgz
    tar xzf rubygems-1.4.2.tgz
    cd rubygems-1.4.2
    sudo ruby setup.rb
    cd ..
}

install_ruby19() {
    sudo yum install -y patch wget
    wget http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.2-p290.tar.gz
    tar xzf ruby-1.9.2-p290.tar.gz
    PREFIX=/mnt/data/ruby19
    cd ruby-1.9.2-p290
    ./configure --prefix=$PREFIX
    make
    sudo make install
    sudo mv /usr/bin/ruby /usr/bin/ruby.old
    sudo cp $PREFIX/bin/ruby /usr/bin/
    echo "export PATH=$PREFIX/bin:\$PATH" >> ~/.bash_profile
    source ~/.bash_profile
    cd ..
}

case "$SERVER_TYPE" in
    torquebox)
        # Install necessary RPMs
        sudo yum install -y java-1.6.0-openjdk java-1.6.0-openjdk-devel wget unzip
        # Install latest TorqueBox dev build
        wget http://torquebox.org/2x/builds/LATEST/torquebox-dist-bin.zip
        unzip torquebox-dist-bin.zip
        ln -s torquebox-2*/ torquebox-current
        echo "export TORQUEBOX_HOME=/mnt/data/torquebox-current" >> ~/.bash_profile
        echo "export JBOSS_HOME=\$TORQUEBOX_HOME/jboss" >> ~/.bash_profile
        echo "export JRUBY_HOME=\$TORQUEBOX_HOME/jruby" >> ~/.bash_profile
        echo "export PATH=\$JRUBY_HOME/bin:\$PATH" >> ~/.bash_profile
        source ~/.bash_profile
        jruby -S gem install jruby-openssl
        # Increase maximum heap size
        sed -i 's/-Xmx512m/-Xmx2048m/' $JBOSS_HOME/bin/standalone.conf
        # Increase open file limit
        echo "ec2-user hard nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ec2-user shoft nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ulimit -n 4096" >> ~/.bash_profile
        echo "Please log out and back in to finish the installation"
        ;;
    torquebox_1)
        # Install necessary RPMs
        sudo yum install -y java-1.6.0-openjdk java-1.6.0-openjdk-devel wget unzip
        # Install latest TorqueBox 1.x build
        wget http://repository-torquebox.forge.cloudbees.com/release/org/torquebox/torquebox-dist/1.1.1/torquebox-dist-1.1.1-bin.zip
        unzip torquebox-dist-1.1.1-bin.zip
        ln -s torquebox-1.1.1/ torquebox-current
        echo "export TORQUEBOX_HOME=/mnt/data/torquebox-current" >> ~/.bash_profile
        echo "export JBOSS_HOME=\$TORQUEBOX_HOME/jboss" >> ~/.bash_profile
        echo "export JRUBY_HOME=\$TORQUEBOX_HOME/jruby" >> ~/.bash_profile
        echo "export PATH=\$JRUBY_HOME/bin:\$PATH" >> ~/.bash_profile
        source ~/.bash_profile
        jruby -S gem install jruby-openssl
        # Increase maximum heap size
        sed -i 's/-Xmx1024m/-Xmx2048m/' $JBOSS_HOME/bin/run.conf
        # Increase open file limit
        echo "ec2-user hard nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ec2-user shoft nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ulimit -n 4096" >> ~/.bash_profile
        echo "Please log out and back in to finish the installation"
        ;;
    trinidad)
        install_jruby
        jruby -S gem install trinidad
        # Increase open file limit
        echo "ec2-user hard nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ec2-user shoft nofile 4096" | sudo tee -a /etc/security/limits.conf
        echo "ulimit -n 4096" >> ~/.bash_profile
        echo "Please log out and back in to finish the installation"
        ;;
    glassfish)
        install_jruby
        jruby -S gem install glassfish
        echo "Please log out and back in to finish the installation"
        ;;
    passenger)
        install_ruby
        sudo gem install passenger
        ;;
    passenger_ree)
        install_ruby
        install_ree
        sudo gem install passenger
        echo "Please log out and back in to finish the installation"
        ;;
    passenger_19)
        install_ruby
        install_ruby19
        sudo gem install passenger
        echo "Please log out and back in to finish the installation"
        ;;
    unicorn)
        install_ruby
        sudo gem install unicorn rake
        ;;
    unicorn_ree)
        install_ruby
        install_ree
        sudo gem install unicorn rake
        echo "Please log out and back in to finish the installation"
        ;;
    unicorn_19)
        install_ruby
        install_ruby19
        sudo gem install unicorn rake
        echo "Please log out and back in to finish the installation"
        ;;
    thin)
        install_ruby
        sudo gem install thin rake
        ;;
esac

echo ""
echo "$SERVER_TYPE Server Setup Finished Successfully"
echo ""
