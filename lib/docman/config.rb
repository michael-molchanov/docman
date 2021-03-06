require 'singleton'
require 'hash_deep_merge'
require 'digest/md5'
require 'json'

module Docman
  class Config < Hash

    attr_reader :unmutable_config

    @loaded_scenario_sources

    def initialize(file)
      super
      @config = YAML::load_file(file)
      @loaded_scenario_sources = {}
      assign_to_self
    end

    def assign_to_self
      @config.each_pair do |k, v|
        self[k] = v
      end
      @unmutable_config = Marshal::load(Marshal.dump(@config))
    end

    def merge_config_from_file(docroot_dir, docroot_config_dir, config_file, options = nil)
      file = File.join(docroot_config_dir, config_file)
      if File.file?(file)
        config = YAML::load_file(file)
        if config['scenarios']
          scenarios_path = File.join(docroot_dir, '.docman/scenarios')
          `rm -fR #{scenarios_path}` if File.directory? scenarios_path
          `mkdir -p #{scenarios_path}`
          unless config['scenarioSources']
            config['scenarioSources'] = {}
          end
          config['scenarioSources']['root_config'] = {}
          config['scenarioSources']['root_config']['dir'] = docroot_config_dir
          @loaded_scenario_sources['root_config'] = config['scenarioSources']['root_config']
          config = merge_scenarios_configs(config, {}, scenarios_path, 'root_config')
        end
      end
      unless config.nil?
        unless config['override_docman_default'].nil?
          self.clear
          @config = config
        else
          @config.deep_merge!(config)
        end
        @config['version'] = config['version'].nil? ? 1 : config['version']
      end

      assign_to_self
    end

    def merge_scenarios_configs(config, temp_config = {}, scenarios_path, current_scenario_source_name)
      temp_config.deep_merge!(config)
      scenarios_config = {}
      unless config['scenarios'].nil?
        config['scenarios'].each do |s|
          scenario = {}
          if s.is_a? String
            values = s.split(':')
            if values.size() > 1
              scenario_source_name = values[0]
              scenario_name = values[1]
            else
              scenario_source_name = current_scenario_source_name
              scenario_name = values[0]
            end
            scenario['name'] = scenario_name
            if temp_config['scenarioSources'].key? scenario_source_name
              temp_config['scenarioSources'][scenario_source_name]['dir']
              scenario_source_path = temp_config['scenarioSources'][scenario_source_name]['dir'] ? temp_config['scenarioSources'][scenario_source_name]['dir'] : File.join(scenarios_path, scenario_source_name)
              if @loaded_scenario_sources.key? scenario_source_name
                scenario['source'] = @loaded_scenario_sources[scenario_source_name]
              else
                `rm -fR #{scenario_source_path}` if File.directory? scenario_source_path
                scenario['source'] = temp_config['scenarioSources'][scenario_source_name]
                scenario['source']['ref'] = scenario['source']['ref'] ? scenario['source']['ref'] : 'master'
                GitUtil.clone_repo(scenario['source']['repo'], scenario_source_path, 'branch', scenario['source']['ref'], true, 1)
                @loaded_scenario_sources[scenario_source_name] = scenario['source']
              end
              scenario_config_file = File.join(scenario_source_path, 'scenarios', scenario['name'], 'config.yaml')
              if File.file? scenario_config_file
                scenario_config = merge_scenarios_configs(YAML::load_file(scenario_config_file), temp_config, scenarios_path, scenario_source_name)
                scenarios_config.deep_merge!(scenario_config)
                puts "Loaded scenario #{scenario['name']} from source #{scenario_source_name}"
              end
            end
          end
        end
      end
      scenarios_config.deep_merge!(config)
    end

    def config_hash
      Digest::MD5.hexdigest(Marshal::dump(@unmutable_config))
    end

    def version
      @config['version']
    end

  end
end
