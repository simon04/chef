#
# Cookbook:: planet
# Recipe:: dump
#
# Copyright:: 2013, OpenStreetMap Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "yaml"

include_recipe "accounts"
include_recipe "osmosis"

db_passwords = data_bag_item("db", "passwords")

package %w[
  postgresql-client
  ruby
  ruby-dev
  ruby-libxml
  make
  gcc
  libpq-dev
  osmdbt
]

gem_package "pg"

remote_directory "/opt/flush" do
  source "flush"
  owner "root"
  group "root"
  mode "755"
  files_owner "root"
  files_group "root"
  files_mode "755"
end

execute "/opt/flush/Makefile" do
  action :nothing
  command "make"
  cwd "/opt/flush"
  user "root"
  group "root"
  subscribes :run, "remote_directory[/opt/flush]"
end

remote_directory "/usr/local/bin" do
  source "replication-bin"
  owner "root"
  group "root"
  mode "755"
  files_owner "root"
  files_group "root"
  files_mode "755"
end

template "/usr/local/bin/replicate-minute" do
  source "replicate-minute.erb"
  owner "root"
  group "root"
  mode "755"
end

template "/usr/local/bin/users-agreed" do
  source "users-agreed.erb"
  owner "root"
  group "root"
  mode "755"
end

template "/usr/local/bin/users-deleted" do
  source "users-deleted.erb"
  owner "root"
  group "root"
  mode "755"
end

remote_directory "/store/planet/users_deleted" do
  source "users_deleted"
  owner "planet"
  group "planet"
  mode "755"
  files_owner "root"
  files_group "root"
  files_mode "644"
end

remote_directory "/store/planet/replication" do
  source "replication-cgi"
  owner "root"
  group "root"
  mode "755"
  files_owner "root"
  files_group "root"
  files_mode "755"
end

directory "/store/planet/replication/changesets" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/planet/replication/day" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/planet/replication/hour" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/planet/replication/minute" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/planet/replication/test" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/planet/replication/test/minute" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/replication" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/store/replication/minute" do
  owner "planet"
  group "planet"
  mode "755"
end

systemd_tmpfile "/run/replication" do
  type "d"
  owner "planet"
  group "planet"
  mode "755"
end

directory "/etc/replication" do
  owner "root"
  group "root"
  mode "755"
end

directory "/var/run/lock/changeset-replication/" do
  owner "planet"
  group "planet"
  mode "750"
end

template "/etc/replication/auth.conf" do
  source "replication.auth.erb"
  user "root"
  group "planet"
  mode "640"
  variables :password => db_passwords["planetdiff"]
end

osmdbt_config = {
  "database" => {
    "host" => node[:web][:database_host],
    "dbname" => "openstreetmap",
    "user" => "planetdiff",
    "password" => db_passwords["planetdiff"],
    "replication_slot" => "osmdbt"
  },
  "log_dir" => "/var/lib/replication/minute",
  "changes_dir" => "/store/planet/replication/test/minute",
  "tmp_dir" => "/store/replication/minute",
  "run_dir" => "/run/replication"
}

file "/etc/replication/osmdbt-config.yaml" do
  user "root"
  group "planet"
  mode "640"
  content YAML.dump(osmdbt_config)
end

systemd_service "replication-minutely" do
  description "Minutely replication"
  user "planet"
  working_directory "/etc/replication"
  exec_start "/usr/local/bin/replicate-minute"
  private_tmp true
  private_devices true
  protect_system "full"
  protect_home true
  restrict_address_families %w[AF_INET AF_INET6]
  no_new_privileges true
end

systemd_timer "replication-minutely" do
  description "Minutely replication"
  on_boot_sec 60
  on_unit_active_sec 60
  accuracy_sec 5
end

template "/etc/replication/changesets.conf" do
  source "changesets.conf.erb"
  user "root"
  group "planet"
  mode "640"
  variables :password => db_passwords["planetdiff"]
end

template "/etc/replication/users-agreed.conf" do
  source "users-agreed.conf.erb"
  user "planet"
  group "planet"
  mode "600"
  variables :password => db_passwords["planetdiff"]
end

directory "/var/lib/replication" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/var/lib/replication/minute" do
  owner "planet"
  group "planet"
  mode "755"
end

directory "/var/lib/replication/hour" do
  owner "planet"
  group "planet"
  mode "755"
end

template "/var/lib/replication/hour/configuration.txt" do
  source "replication.config.erb"
  owner "planet"
  group "planet"
  mode "644"
  variables :base => "minute", :interval => 3600
end

link "/var/lib/replication/hour/data" do
  to "/store/planet/replication/hour"
end

directory "/var/lib/replication/day" do
  owner "planet"
  group "planet"
  mode "755"
end

template "/var/lib/replication/day/configuration.txt" do
  source "replication.config.erb"
  owner "planet"
  group "planet"
  mode "644"
  variables :base => "hour", :interval => 86400
end

link "/var/lib/replication/day/data" do
  to "/store/planet/replication/day"
end

if node[:planet][:replication] == "enabled"
  cron_d "users-agreed" do
    minute "0"
    hour "7"
    user "planet"
    command "/usr/local/bin/users-agreed"
    mailto "zerebubuth@gmail.com"
  end

  cron_d "users-deleted" do
    minute "0"
    hour "17"
    user "planet"
    command "/usr/local/bin/users-deleted"
    mailto "zerebubuth@gmail.com"
  end

  cron_d "replication-changesets" do
    user "planet"
    command "/usr/local/bin/replicate-changesets /etc/replication/changesets.conf"
    mailto "zerebubuth@gmail.com"
  end

  service "replication-minutely.timer" do
    action [:enable, :start]
  end

  cron_d "replication-minutely" do
    user "planet"
    command "/usr/local/bin/osmosis -q --replicate-apidb authFile=/etc/replication/auth.conf validateSchemaVersion=false --write-replication workingDirectory=/store/planet/replication/minute"
    mailto "brett@bretth.com"
    environment "LD_PRELOAD" => "/opt/flush/flush.so"
  end

  cron_d "replication-hourly" do
    minute "2,7,12,17"
    user "planet"
    command "/usr/local/bin/osmosis -q --merge-replication-files workingDirectory=/var/lib/replication/hour"
    mailto "brett@bretth.com"
    environment "LD_PRELOAD" => "/opt/flush/flush.so"
  end

  cron_d "replication-daily" do
    minute "5,10,15,20"
    user "planet"
    command "/usr/local/bin/osmosis -q --merge-replication-files workingDirectory=/var/lib/replication/day"
    mailto "brett@bretth.com"
    environment "LD_PRELOAD" => "/opt/flush/flush.so"
  end
else
  cron_d "users-agreed" do
    action :delete
  end

  cron_d "users-deleted" do
    action :delete
  end

  cron_d "replication-changesets" do
    action :delete
  end

  service "replication-minutely.timer" do
    action [:stop, :disable]
  end

  cron_d "replication-minutely" do
    action :delete
  end

  cron_d "replication-hourly" do
    action :delete
  end

  cron_d "replication-daily" do
    action :delete
  end
end
