require 'pathname'

require 'rom/types'
require 'rom/initializer'
require 'rom/sql/migration'
require 'rom/sql/migration/inline_runner'

module ROM
  module SQL
    module Migration
      # @api private
      class Migrator
        extend Initializer

        DEFAULT_PATH = 'db/migrate'.freeze
        VERSION_FORMAT = '%Y%m%d%H%M%S'.freeze
        DEFAULT_INFERRER = Schema::Inferrer.new.suppress_errors.freeze

        param :connection

        option :path, type: ROM::Types.Definition(Pathname), default: -> { DEFAULT_PATH }

        option :inferrer, default: -> { DEFAULT_INFERRER }

        option :runner, default: -> { InlineRunner.new(connection) }

        # @api private
        def run(options = {})
          Sequel::Migrator.run(connection, path.to_s, options)
        end

        # @api private
        def pending?
          !Sequel::Migrator.is_current?(connection, path.to_s)
        end

        # @api private
        def migration(&block)
          Sequel.migration(&block)
        end

        # @api private
        def create_file(name, version = generate_version)
          filename = "#{version}_#{name}.rb"
          dirname = Pathname(path)
          fullpath = dirname.join(filename)

          FileUtils.mkdir_p(dirname)
          File.write(fullpath, migration_file_content)

          fullpath
        end

        # @api private
        def generate_version
          Time.now.utc.strftime(VERSION_FORMAT)
        end

        # @api private
        def migration_file_content
          File.read(Pathname(__FILE__).dirname.join('template.rb').realpath)
        end

        # @api private
        def auto_migrate!(gateway, schemas)
          diff_finder = SchemaDiff.new

          changes = schemas.map { |_, target|
            empty = SQL::Schema.define(target.name)
            current = target.with(inferrer.(empty, gateway))
            current.set_foreign_keys!(schemas)

            diff_finder.(current, target)
          }.reject(&:empty?)

          runner.(changes)
        end
      end
    end
  end
end
