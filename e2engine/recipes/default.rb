#
# Cookbook Name:: e2engine
# Recipe:: default
#
# Copyright 2012, Everything2 Media LLC
#
# You are free to use/modify these files under the same terms as the Everything Engine itself

require 'json'
require 'net/http'
require 'uri'

everythingdir = "/var/everything"

# Minor copy and paste from e2cron
logdir = "/var/log/everything"
datelog = "`date +\\%Y\\%m\\%d\\%H`.log"

directory logdir do
  owner "www-data"
  group "root"
  mode 0755
  action :create
end

to_install = [
    'perl',
    'libalgorithm-diff-perl',
    'libarchive-zip-perl',
    'libcgi-pm-perl',
    'libcache-perl',
    'libcache-memcached-perl',
    'libdbi-perl',
    'libdate-calc-perl',
    'libdatetime-perl',
    'libdatetime-format-strptime-perl',
    'libhtml-tiny-perl',
    'libheap-perl',
    'libio-string-perl',
    'perlmagick',
    'libjson-perl',
    'libxml-generator-perl',
    'libxml-simple-perl',
    'libyaml-perl',
    'libapache-dbi-perl',
    'libclone-perl',
    'libtest-deep-perl',
    'libdevel-caller-perl',
    'libdbd-mysql-perl',
    'git',
    'libnet-amazon-s3-perl',
    'libemail-sender-perl',
    'libnet-smtp-ssl-perl',
    'libauthen-sasl-perl',
    'libxml-rss-perl',
    'libmoose-perl',
    'libnamespace-autoclean-perl',
    'libwww-perl',
    'libperl-critic-perl',
    'libmason-perl',
    'libtry-tiny-perl',
    'yui-compressor',
    'libapache-db-perl',
    'libdevel-nytprof-perl',
    'libdevel-cycle-perl',
# Practical helper utils
    'strace',
    'vim',
    'locate',
    'screen',
    'mysql-client',
    'xz-utils',
    'xdelta3',
# Needed for Amazon provisioning testing and building
    'ruby',
    'ruby-dev',
    'ruby-bundler'
]

to_install.each do |p|
  package p
end

gem_package 'aws-sdk' do
  timeout 240
end

git everythingdir do
  repository node["e2engine"]["gitrepo"]
  enable_submodules true
  action :sync
end

directory '/etc/everything' do
  owner "root"
  group "root"
  mode "0755"
  action "create"
end

directory '/var/mason' do
  owner "www-data"
  group "www-data"
  mode 0755
  action "create"
end

nosearch_words = ['a','an','and','are','at','definition','everything','for','if','in','is','it','my','new','node','not','of','on','that','the','thing','this','to','we','what','why','with','writeup','you','your']
nosearch_words_hash = {}
nosearch_words.each { |x| nosearch_words_hash[x] = 1 }

everything_conf_variables = {
    "basedir" => everythingdir,
    "s3host" => node["e2engine"]["s3host"],
    "guest_user" => node["e2engine"]["guest_user"],
    "site_url" => node["e2engine"]["site_url"],
    "infected_ips" => node["e2engine"]["infected_ips"],
    "default_style" => node["e2engine"]["default_style"],
    "everyuser" => node["e2engine"]["everyuser"],
    "everypass" => node["e2engine"]["everypass"],
    "everything_dbserv" => node["e2engine"]["everything_dbserv"],
    "database" => node["e2engine"]["database"],
    "cookiepass" => node["e2engine"]["cookiepass"],
    "canonical_web_server" => node["e2engine"]["canonical_web_server"],
    "homenode_image_host" => node["e2engine"]["homenode_image_host"],
    "smtp_host" => node["e2engine"]["smtp_host"],
    "smtp_use_ssl" => node["e2engine"]["smtp_use_ssl"],
    "smtp_port" => node["e2engine"]["smtp_port"],
    "smtp_user" => node["e2engine"]["smtp_user"],
    "smtp_pass" => node["e2engine"]["smtp_pass"],
    "mail_from" => node["e2engine"]["mail_from"],
    "environment" => node["e2engine"]["environment"],
    "notification_email" => node["e2engine"]["notification_email"],
    "nodecache_size" => node["e2engine"]["nodecache_size"],
    "s3" => node["e2engine"]["s3"].to_hash,
    "certificate_manager" => node["e2engine"]["certificate_manager"].to_hash,
    "static_nodetypes" => node["e2engine"]["static_nodetypes"],
    "memcache" => node["e2engine"]["memcache"].to_hash,
    "clean_search_words_aggressively" => node["e2engine"]["clean_search_words_aggressively"],
    "search_row_limit" => node["e2engine"]["search_row_limit"],
    "logdirectory" => node["e2engine"]["logdirectory"],
    "use_local_javascript" => node["e2engine"]["use_local_javascript"],
    "system" => node["e2engine"]["system"].to_hash,
    "permanent_cache" => {
      "usergroup" => 1,
      "container" => 1,
      "htmlcode" => 1,
      "maintenance" => 1,
      "setting" => 1,
      "fullpage" => 1,
      "nodetype" => 1,
      "writeuptype" => 1,
      "linktype" => 1,
      "sustype" => 1,
      "nodelet" => 1,
      "datastash" => 1,
      "theme" => 1
    },
    "nosearch_words" => nosearch_words_hash,
    "create_room_level" => node["e2engine"]["create_room_level"],
    "stylesheet_fix_level" => node["e2engine"]["stylesheet_fix_level"],
    "maintenance_mode" => node["e2engine"]["maintenance_mode"],
    "writeuplowrepthreshold" => node["e2engine"]["writeuplowrepthreshold"],
    "google_ads_badnodes" => node["e2engine"]["google_ads_badnodes"],
    "google_ads_badwords" => node["e2engine"]["google_ads_badwords"]
}

file '/etc/everything/everything.conf.json' do
  owner "www-data"
  group "www-data"
  content JSON.pretty_generate(everything_conf_variables)
  mode "0755"
end

# Amazon-specific config
require 'aws-sdk'

@instance_server='http://169.254.169.254/latest'

def query_metadata(value)
  Net::HTTP.get(URI("#{@instance_server}/#{value}"))
end

def instance_identity
  JSON.parse(query_metadata('dynamic/instance-identity/document'))
end

def instance_region
  instance_identity['region']
end

@rds = Aws::RDS::Client.new(region: instance_region)
@elb = Aws::ElasticLoadBalancingV2::Client.new(region: instance_region)

def instance_id
  instance_identity['instanceId']
end

def mac_address
  query_metadata('meta-data/network/interfaces/macs/').split("\n")[0].gsub!(%r{/$},'')
end

def public_address
  query_metadata("meta-data/network/interfaces/macs/#{mac_address}/public-ipv4s").split("\n")[0]
end

def frontend_elb
  @elb.describe_load_balancers.load_balancers.each do |elb|
    @elb.describe_tags(resource_arns: [elb['load_balancer_arn']]).tag_descriptions[0]['tags'].each do |tag|
      return elb if tag['key'].eql? 'app' and tag['value'].eql? 'e2'
    end
  end
  nil
end

def web_cluster_target_group
  @elb.describe_target_groups.target_groups.each do |tg|
    return tg if tg['protocol'].eql? 'HTTPS' and tg['load_balancer_arns'].include?(frontend_elb['load_balancer_arn'])
  end
  nil
end

if node['environment'].eql? 'production'
  Chef::Log.info('In production, doing instance registrations')
else

  Chef::Log.info('Setting up ingress to production DB')
  begin
    @rds.authorize_db_security_group_ingress(db_security_group_name: 'default', cidrip: "#{public_address}/32")
  rescue Aws::RDS::Errors::AuthorizationAlreadyExists
  end

  Chef::Log.info("Run list: #{node.run_list.join(',')}")
  if node.run_list?('recipe[e2web]')
    Chef::Log.info("Registering web to target")
    @elb.register_targets(target_group_arn: web_cluster_target_group['target_group_arn'], targets: [{id: instance_id}]) 
  else
    Chef::Log.info("Not a webhead, not registering to target")
  end

else
  Chef::Log.info('Not in production, not doing instance registrations')
end
