#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# A slightly more generalised alternative to RANCID - still pretty rancid though.

require 'fileutils'
require 'json'
require 'pp'
require 'net/ssh'
require 'open3'
require 'time_diff'

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

        if @config["hosts"].nil? or @config["hosts"].empty?
          raise "No hosts configured, tried #{@files.join(", ")}"
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

      def commit_message(host)
        hostconfig(host)["git"]["commit-message"]
      end

      def repo(host)
        hostconfig(host)["pool"] + "/" + host.split(".").reverse.join("/")
      end

      def logdir
        @config["default"]["pool"] + "/log"
      end

      def logname
        "status"
      end

    end

    def initialize
      @configuration = Configuration.new
    end

    def log_start(message)
      logdir = @configuration.logdir
      FileUtils.mkpath(logdir) unless Dir.exists?(logdir)
      abort("Logdir (#{logdir}) unavailable!") unless ( Dir.exists?(logdir) && File.writable?(logdir))
      logfile = @configuration.logdir + "/" + @configuration.logname
      file = File.open(logfile, "w")
      abort("Logfile (#{logfile}) not writeable!") if file.nil?
      file.puts(message)
      file.close
    end

    def log_append(message)
      logfile = @configuration.logdir + "/" + @configuration.logname
      file = File.open(logfile, "a")
      abort("Logfile (#{logfile}) not writeable!") if file.nil?
      file.puts(message)
      file.close
    end

    def log_commit
      logdir = @configuration.logdir
      abort("Unable to change directory to #{logdir}!") unless Dir.chdir(logdir)
      commit_to_git(@configuration.config["default"]["git"]["author"], "log", "automatic backup complete")
    end

    def perform_backups
      log_start("Last backup started at : #{Time.now}")
      log_append("\nHosts : #{@configuration.hosts.join(", ")}")
      results = { ok: 0, fail: 0, disabled: 0 }
      @configuration.hosts.each do |host|
        begin
	  if host.start_with?("-") 
	    puts "Skipping disabled host : #{host}"
	    results[:disabled] += 1
	  else
            if perform_backup(host, @configuration.hostconfig(host))
              results[:ok] += 1
	    else
	      results[:fail] += 1
	    end
	  end
        rescue Exception => e
          results[:fail] += 1
          puts e.to_s
        end
      end
      log_append("Completed at : #{Time.now}")
      log_append("#{results[:ok]} hosts OK, #{results[:fail]} hosts failed, #{results[:disabled]} hosts disabled.")
      puts("#{results[:ok]} hosts OK, #{results[:fail]} hosts failed, #{results[:disabled]} hosts disabled.")
      log_commit
    end

    def perform_backup(host, config)
      start = Time.now
      repo = @configuration.repo(host)
      FileUtils.mkpath(repo) unless Dir.exist?(repo)
      abort("Unable to change directory to #{repo}.") unless Dir.chdir(repo)

      config["user"] = ENV["USER"] if config["user"].empty?

      result = {}
      ssh_status = false
      error = ""
      begin
      	Net::SSH.start(host, config["user"]) do |ssh|
          @configuration.commands(host).each do |cmd|
            result[cmd] = ssh.exec!("show #{cmd}")
          end
        end
        result.each_pair do |k,v|
          File.write(k, v)
        end
	ssh_status = true
      rescue Net::SSH::Proxy::ConnectError => e
	ssh_status = false
	error = e.to_s
      end

      fin = Time.now
      elapsed = Time.diff(fin, start)
      if (ssh_status)
        commit_to_git(@configuration.author(host), host, @configuration.commit_message(host))
	puts "#{start} : Backup of #{host} complete in #{elapsed[:diff]}"
      else
	puts "#{start} : Backup of #{host} failed after #{elapsed[:diff]} \n\t\tbecause of #{error}"
      end
      return ssh_status
    end

    # Commits any and all changes in cwd to git
    def commit_to_git(author, host, commit_message)
      message = ""
      ret = Open3.popen2e("git", "init") do |i,o,t|
        message = o.read
        t.value.exitstatus
      end
      if ret != 0
        puts "git init failed for #{host} with returnvalue #{ret} and message :"
        puts message
      else
        ret = Open3.popen2e("git", "add", ".") do |i,o,t|
          message = o.read
          t.value.exitstatus
        end
        if ret != 0
          puts "git add failed for #{host} with returnvalue #{ret} and message :"
          puts message
        else
          ret = Open3.popen2e("git", "commit", "-m", commit_message, "--author", author) do |i,o,t|
            message = o.read
            t.value.exitstatus
          end
          if ret != 0
            unless message.match(/nothing to commit/)
              puts "git commit failed for #{host} with returnvalue #{ret} and message :"
              puts message
            end
          end
        end
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
