#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# A slightly more generalised alternative to RANCID - still pretty rancid though.

require 'fileutils'
require 'json'
require 'pp'
require 'net/ssh'
require 'git'

class Hash
   def deep_merge(hash)
      target = dup
      hash.keys.each do |key|
         if hash[key].is_a? Hash and self[key].is_a? Hash
            target[key] = target[key].deep_merge(hash[key])
            next
         end
         target[key] = hash[key]
      end
      target
   end
end

module Network

  class Backup

    attr_reader :configuration
    
    class Configuration
      
      attr_reader :config
      attr_reader :files
      attr_reader :commands
      attr_reader :configuration_files_used

      def sanity_check(config_part, config_keys)
        config_keys.each do |key|
          abort("Missing key :#{key} in #{config_part}") if config_part[key].nil?
        end
      end
      
      def initialize
        @files = ["default_config.json", "/etc/network-backup/config.json", "#{ENV["HOME"]}/.config/network-backup/config.json" ]
        @config = {}
        @configuration_files_used = []
        @files.each do |file|
          if File.readable?(file)
            c = JSON.parse(File.read(file))
            @config = @config.deep_merge(c) if c
            @configuration_files_used << file
          end
        end

        # Make sure we have the minimum of expected configuration-keys
        sanity_check(@config, ["default"])
        sanity_check(@config["default"], ["pool", "filter", "git", "user", "type", "login"])
        
        # And at least an empty hash for the per-host configuration
        if @config["host-configuration"].nil?
          @config["host-configuration"] = {}
        end

        # expand config["host-configuration][host] elements
        # This way each host will have a complete
        # configuration in @config["host-configuration"][hostname]
        @config["hosts"].each do |host|
          if @config["host-configuration"][host].nil?
            @config["host-configuration"][host] = @config["default"]
          else
            @config["host-configuration"][host] = @config["default"].deep_merge(@config["host-configuration"][host])
          end
        end
      end

      def hosts
        @config["hosts"]
      end

      def hostconfig(host)
        @config["host-configuration"][host]
      end

      def commands(host)
        @config["device-types"][hostconfig(host)["type"]]["commands"]
      end

      def author(host)
        hostconfig(host)["git"]["author"]
      end

    end

    def initialize
      @configuration = Configuration.new
    end

    def perform_backups
      @configuration.hosts.each do |host|
        perform_backup(host, @configuration.hostconfig(host))
      end
    end

    def perform_backup(host, config)
      puts "Backing up #{host}"

      repo = config["pool"] + "/" + host.split(".").reverse.join("/")
      FileUtils.mkpath(repo) unless Dir.exist?(repo)
      abort("Unable to change directory to #{repo}.") unless Dir.chdir(repo)

      config["user"] = ENV["USER"] if config["user"].empty?

      result = {}
      Net::SSH.start(host, config["user"]) do |ssh|
        @configuration.commands(host).each do |cmd|
          result[cmd] = ssh.exec!("show #{cmd}")
        end
      end
      result.each_pair do |k,v|
        File.write(k, v)
      end
      git = Git.init
      if ! (git.status.changed.empty? || git.status.untracked.empty?)
        git.add(all: true)
        git.commit_all("automatic backup", author: @configuration.author(host))
      end
    end

    def dump_configuration
      pp @configuration.configuration_files_used
      pp @configuration.config
    end
    
  end
end

agent = Network::Backup.new

agent.perform_backups

#agent.dump_configuration
