#!/usr/bin/env ruby

# A slightly more generalised alternative to RANCID - still pretty rancid though.

require 'fileutils'
require 'json'

def read_configuration
  # Read configuration from these files
  config_files = ["default_config.json", "/etc/network-backup/config.json", "#{ENV["HOME"]}/.config/network-backup/config.json"]
  configuration = {}
  # Merge all configurations
  config_files.each do |file|
    if File.readable?(file)
      c = JSON.parse(File.read(file))
      configuration.merge!(c) if c
    end
  end
  # Return complete configuration
  configuration
end

def user_for(host)
  ENV["USERNAME"]
end

def pool(host)
  "#{ENV["HOME"]}/backup/network"
end

def target_repo(host)
  pool(host) + "/" + host.split(".").reverse.join("/")
end

def commands_for(host)
  ["version", "config", "chassis environment", "chassis firmware", "chassis hardware detail", "chassis alarm", "interfaces brief", "system boot-messages",
   "system core-dumps", "system license", "vlans", "system commit"]
end

def perform_backup(host)
  repo = target_repo(host)
  commands = commands_for(host)
  username = user_for(host)
  FileUtils.mkpath(repo) unless Dir.exist?(repo)
  abort unless Dir.chdir(repo)
  commands.each do |command|
    system "ssh #{username}@#{host} show #{command} > '#{command}'"
  end
  f = File.open("config", "r")
  commit_msg = f.readline.strip
  system "git init"
  system "git add ."
  system "git commit -m '#{commit_msg}'"
end

def dump_config(config)
  puts "default : #{config["default"]}"

  config["hosts"].each do |host|
    hostconfig = config["default"]
    if config["host-configuration"][host]
      hostconfig.merge!(config["host-configuration"][host])
    end
    puts "#{host} : #{hostconfig}"
  end
end

config = read_configuration
dump_config(config)

ARGV.each do |host|
  perform_backup(host)
end
