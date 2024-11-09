require 'csv'
require 'json'
require 'yaml'
require 'zip'
require 'sqlite3'
require 'mongo'
require 'pony'

require_relative "./parsers/simple_website_parser"
require_relative "./models/item"
require_relative "./models/database_connector"

module RbParser
  class Engine
    attr_reader :parser, :config, :db_connector

    def initialize(config_path, db_config_path)
      @config_path = config_path
      @db_connector = DatabaseConnector.new(db_config_path)
      load_config
      initialize_parser
    end

    def load_config
      @config = YAML.load_file(@config_path)
      puts "Configuration loaded successfully from #{@config_path}"
    rescue StandardError => e
      puts "Failed to load configuration: #{e.message}"
    end

    def initialize_parser
      @parser = RbParser::SimpleWebsiteParser.new(@config_path)
    end

    def run
      puts "Running Engine..."
      db_connector.connect_to_databases
      parser.start_parse
      puts "Items collected: #{parser.item_collection.size}"

      parser.item_collection.each_with_index do |item, index|
        puts "Item #{index + 1}: #{item.to_h}"
      end

      if parser.item_collection.empty?
        puts "No items were collected. Check the configuration and selectors."
        return
      end

      if config["methods"].nil? || config["methods"].empty?
        puts "No methods specified in configuration to execute."
      else
        puts "Methods to execute: #{config["methods"].inspect}"
      end

      run_methods(config["methods"])

    ensure
      db_connector.close_connections
    end

    def run_methods(config_params)
      config_params.each do |method_name|
        if respond_to?(method_name)
          send(method_name)
        else
          puts "Method #{method_name} not found or cannot be executed."
        end
      rescue StandardError => e
        puts "Error executing #{method_name}: #{e.message}"
      end
    end

    def run_website_parser
      parser.start_parse
      puts "Website parsing completed with #{parser.item_collection.size} items."
    end

    def run_save_to_csv
      CSV.open("output/data.csv", "w") do |csv|
        csv << ["Name", "Price", "Description", "Category", "Image Path"]
        parser.item_collection.each do |item|
          csv << [item.name, item.price, item.description, item.category, item.image_path]
        end
      end
      puts "Data saved to CSV at output/data.csv"
    end

    def run_save_to_json
      data = parser.item_collection.map(&:to_h)
      File.write("output/data.json", JSON.pretty_generate(data))
      puts "Data saved to JSON at output/data.json"
    end

    def run_save_to_yaml
      data = parser.item_collection.map(&:to_h)
      File.write("output/data.yaml", data.to_yaml)
      puts "Data saved to YAML at output/data.yaml"
    end

    def run_save_to_sqlite
      db = db_connector.sqlite_db
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS items (
          id INTEGER PRIMARY KEY,
          name TEXT,
          price TEXT,
          description TEXT,
          category TEXT,
          image_path TEXT
        );
      SQL

      parser.item_collection.each do |item|
        db.execute("INSERT INTO items (name, price, description, category, image_path) 
                    VALUES (?, ?, ?, ?, ?)", 
                    [item.name, item.price, item.description, item.category, item.image_path])
      end
      puts "Data saved to SQLite at #{db_connector.config['database']['path']}"
    end

    def run_save_to_mongodb
      client = db_connector.mongodb_client
      items_collection = client[:items]

      data = parser.item_collection.map(&:to_h)
      items_collection.insert_many(data)
      puts "Data saved to MongoDB in database '#{db_connector.config['database']['name']}'"
    end

    # def archive_results
    #   Zip::File.open("output/results.zip", Zip::File::CREATE) do |zipfile|
    #     Dir["output/*"].each do |file|
    #       zipfile.add(File.basename(file), file)
    #     end
    #   end
    #   puts "Results archived to output/results.zip"
    #   ArchiveSender.perform_async("output/results.zip", config["email"])
    # end
  end
end
