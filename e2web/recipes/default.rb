#
# Cookbook Name:: e2web
# Recipe:: default
#
# Copyright 2012, Everything2 Media LLC
#
# You are free to use/modify these files under the same terms as the Everything Engine itself

require 'base64'

to_install = [
    'apache2',
    'libapache2-mod-perl2',
    'build-essential'
]

to_install.each do |p|
  package p
end


if node['platform'].eql? 'ubuntu'
load_modules = ['rewrite','proxy','proxy_http','ssl']
  load_modules.push('perl','mpm_prefork','socache_shmcb')

  ['mpm_event.conf','mpm_event.load'].each do |mod|
    file "/etc/apache2/mods-enabled/#{mod}" do
      action "delete"
      notifies :restart, "service[apache2]", :delayed
    end
  end
end

load_modules.each do |apache_mod|
  link "/etc/apache2/mods-enabled/#{apache_mod}.load" do
    action "create"
    to "../mods-available/#{apache_mod}.load"
    link_type :symbolic
    owner "root"
    group "root"
    notifies :restart, "service[apache2]", :delayed
  end
end

directory "/etc/apache2/conf.d/" do
  owner "www-data"
  group "root"
  mode 0755
  action :create
end


unless node['platform'].eql? 'ubuntu'
  bash "install Linux::Pid" do
    cwd "/tmp"
    user "root"
    creates "/usr/local/lib/perl/5.14.2/auto/Linux/Pid/Pid.so"
    code <<-EOH
    cd /tmp
    rm -rf Linux-Pid*
    wget "http://search.cpan.org/CPAN/authors/id/R/RG/RGARCIA/Linux-Pid-0.04.tar.gz" &>> /tmp/linux-pid.log;
    tar xzvf Linux-Pid-0.04.tar.gz &>> /tmp/linux-pid.log
    cd Linux-Pid-0.04
    perl Makefile.PL INSTALLDIRS=vendor &>> /tmp/linux-pid.log
    make install &>> /tmp/linux-pid.log
    rm -rf Linux-Pid*
    cd ..
    EOH
  end
end

confdir = '/etc/apache2/conf.d'

template "#{confdir}/everything" do
  owner "root"
  group "root"
  mode "0755"
  action "create"
  source 'everything.erb'
  notifies :restart, "service[apache2]", :delayed
end

template '/etc/apache2/mod_rewrite.conf' do
  owner "root"
  group "root"
  mode "0755"
  action "create"
  source "mod_rewrite.conf.erb"
  notifies :restart, "service[apache2]", :delayed
end

template '/etc/apache2/apache2.conf' do
  owner "root"
  group "root"
  mode "0755"
  action "create"
  source 'apache2.conf.erb'
  notifies :restart, "service[apache2]", :delayed
  variables(node["e2web"])
end


template "#{confdir}/ssl.conf" do
  owner "root"
  group "root"
  mode "0755"
  action "create"
  source 'ssl.conf.erb'
  notifies :restart, "service[apache2]", :delayed
  variables(node["e2web"])
end


if node["e2web"]["make_snakeoil_tls_cert"]
  bash "Create E2 snakeoil certs" do
    cwd "/tmp"
    user "root"
    creates "/etc/apache2/e2.key"
    code <<-EOH
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 -batch -keyout /etc/apache2/e2.key -out /etc/apache2/e2.cert -subj '/C=US/ST=MA/L=Maynard/O=Everything2.com/OU=edev/CN=vagranttest.everything2.com'
    EOH
  end
end

bash "Check S3 for certs" do
  cwd "/tmp"
  user "root"
  code "/var/everything/tools/fetch_tls_keys.pl"
end

file '/etc/logrotate.d/apache2' do
  action "delete"
  notifies :restart, "service[apache2]", :delayed
end

# Also in e2cron, e2web
logdir = "/var/log/everything"
datelog = "`date +\\%Y\\%m\\%d\\%H`.log"

if node['platform'].eql? 'ubuntu'
  directory "/var/run/apache2/ssl_mutex" do
    owner "www-data"
    group "root"
    mode 0755
    action :create
    notifies :restart, "service[apache2]", :delayed
  end
end

directory logdir do
  owner "www-data"
  group "root"
  mode 0755
  action :create
  notifies :restart, "service[apache2]", :delayed
end


if node['platform'].eql? 'ubuntu'
  directory '/var/run/apache2/ssl_mutex' do
    owner "www-data"
    group "root"
    mode 0755
    action :create
  end
end


cron 'log_deliver_to_s3.pl' do
  minute '5'
  command "/var/everything/tools/log_deliver_to_s3.pl 2>&1 >> #{logdir}/e2cron.log_deliver_to_s3.#{datelog}"
end

cron 'check for new TLS cert' do
  minute '0'
  hour '3'
  command "/var/everything/tools/fetch_tls_keys.pl 2>&1 >> #{logdir}/e2web.fetch_tls_keys.#{datelog}"
end

service 'apache2' do
  supports :status => true, :restart => true, :reload => true, :stop => true
end

if node['e2engine']['environment'].eql? 'production'
  Chef::Log.info('In production, doing instance registrations')
  bash "AWS: Register instance with application load balancer" do
    code "/var/everything/tools/aws_registration.rb --elb"
  end
else
  Chef::Log.info('Not in production, not doing instance registrations')
end
