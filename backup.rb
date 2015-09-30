#!/usr/bin/env ruby

# A slightly more generalised alternative to RANCID - still pretty rancid though.

require 'fileutils'

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

ARGV.each do |host|
  perform_backup(host)
end
