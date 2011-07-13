require 'active_support/core_ext/string/inflections'
require 'digest/md5'
require 'fileutils'

module FixtureBuilder
  class Configuration
    ACCESSIBLE_ATTRIBUTES = [:select_sql, :delete_sql, :skip_tables, :files_to_check, :record_name_fields,
                             :fixture_builder_file, :after_build, :legacy_fixtures, :model_name_procs]
    attr_accessor *ACCESSIBLE_ATTRIBUTES

    SCHEMA_FILES = ['db/schema.rb', 'db/development_structure.sql', 'db/test_structure.sql', 'db/production_structure.sql']

    def initialize(opts={})
      @legacy_fixtures = Dir.glob(opts[:legacy_fixtures].to_a)
      self.files_to_check += @legacy_fixtures

      @model_name_procs = {}
      @file_hashes = file_hashes
    end

    def include(*args)
      class_eval do
        args.each do |arg|
          include arg
        end
      end
    end

    def factory(&block)
      return unless rebuild_fixtures?
      @builder = Builder.new(self, block).generate!
      write_config
    end

    def custom_names
      @builder.custom_names
    end

    def select_sql
      @select_sql ||= "SELECT * FROM %s"
    end

    def delete_sql
      @delete_sql ||= "DELETE FROM %s"
    end

    def skip_tables
      @skip_tables ||= %w{ schema_migrations }
    end

    def files_to_check
      @files_to_check ||= schema_definition_files
    end

    def schema_definition_files
      Dir['db/*'].inject([]) do |result, file|
        result << file if SCHEMA_FILES.include?(file)
        result
      end
    end

    def files_to_check=(files)
      @files_to_check = files
      @file_hashes = file_hashes
      @files_to_check
    end

    def record_name_fields
      @record_name_fields ||= %w{ unique_name display_name name title username login }
    end

    def fixture_builder_file
      @fixture_builder_file ||= ::Rails.root.join('tmp', 'fixture_builder.yml')
    end

    def name_model_with(model_class, &block)
      @model_name_procs[model_class.table_name] = block
    end

    def name(custom_name, *model_objects)
      raise "Cannot name an object blank" unless custom_name.present?
      model_objects.each do |model_object|
        raise "Cannot name a blank object" unless model_object.present?
        key = [model_object.class.table_name, model_object.id]
        raise "Cannot set name for #{key.inspect} object twice" if custom_names[key]
        custom_names[key] = custom_name
        model_object
      end
    end

    def tables
      ActiveRecord::Base.connection.tables - skip_tables
    end

    def fixtures_dir(path = '')
      File.expand_path(File.join(::Rails.root, spec_or_test_dir, 'fixtures', path))
    end

    private

    def spec_or_test_dir
      File.exists?(File.join(::Rails.root, 'spec')) ? 'spec' : 'test'
    end

    def file_hashes
      files_to_check.inject({}) do |hash, filename|
        hash[filename] = Digest::MD5.hexdigest(File.read(filename))
        hash
      end
    end

    def read_config
      return {} unless File.exist?(fixture_builder_file)
      YAML.load_file(fixture_builder_file)
    end

    def write_config
      FileUtils.mkdir_p(File.dirname(fixture_builder_file))
      File.open(fixture_builder_file, 'w') { |f| f.write(YAML.dump(@file_hashes)) }
    end

    def rebuild_fixtures?
      @file_hashes != read_config
    end
  end
end
